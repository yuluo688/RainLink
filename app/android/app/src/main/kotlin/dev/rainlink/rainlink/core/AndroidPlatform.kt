package dev.rainlink.rainlink.core

import android.content.Context
import android.app.Application
import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.system.OsConstants
import dev.rainlink.core.libbox.ExchangeContext
import dev.rainlink.core.libbox.Func
import dev.rainlink.core.libbox.InterfaceUpdateListener
import dev.rainlink.core.libbox.Libbox
import dev.rainlink.core.libbox.LocalDNSTransport
import dev.rainlink.core.libbox.NetworkInterface as CoreInterface
import dev.rainlink.core.libbox.NetworkInterfaceIterator
import dev.rainlink.core.libbox.Notification
import dev.rainlink.core.libbox.PlatformInterface
import dev.rainlink.core.libbox.StringIterator
import dev.rainlink.core.libbox.TunOptions
import dev.rainlink.core.libbox.WIFIState
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.util.Collections
import java.util.concurrent.Executor

/** Only physical networks are used for core sockets and system DNS. */
internal class AndroidPlatform(
    context: Context,
    private val service: RainlinkVpnService? = null,
    private val operationValid: () -> Boolean = { true },
) : PlatformInterface {
    private val context = context.applicationContext as Application
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    @Volatile private var listener: InterfaceUpdateListener? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val directExecutor = Executor { it.run() }

    private fun physical(): Network? {
        val candidates = connectivity.allNetworks.filter { network ->
            connectivity.getNetworkCapabilities(network)?.let {
                it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    it.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            } == true
        }
        return candidates.firstOrNull { it == connectivity.activeNetwork }
            ?: candidates.firstOrNull { connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
            ?: candidates.firstOrNull()
    }

    fun systemDnsAddress(): String = physical()?.let { connectivity.getLinkProperties(it)?.dnsServers?.firstOrNull()?.hostAddress }
        ?: error("物理网络没有提供 DNS")

    override fun usePlatformAutoDetectInterfaceControl() = true
    override fun autoDetectInterfaceControl(fd: Int) {
        check(operationValid()) { "连接已取消" }
        val vpn = service ?: RainlinkVpnService.current
        if (vpn != null) check(vpn.protect(fd)) { "无法保护核心套接字" }
        val network = physical() ?: error("物理网络不可用")
        ParcelFileDescriptor.fromFd(fd).use { network.bindSocket(it.fileDescriptor) }
    }

    override fun openTun(options: TunOptions): Int {
        check(operationValid()) { "连接已取消" }
        return (service ?: error("测试服务不能创建隧道")).establishTunnel(options)
    }

    fun awaitTunnelReady(interfaceName: String) {
        check(service != null && interfaceName.isNotEmpty()) { "未创建系统隧道" }
        val deadline = SystemClock.elapsedRealtime() + TUN_READY_TIMEOUT_MS
        while (true) {
            check(operationValid() && RainlinkVpnService.current === service) { "连接已取消" }
            // libbox's control listener can be ready before Android registers
            // the VPN network. Confirm this exact TUN before reporting success.
            if (connectivity.allNetworks.any { network ->
                connectivity.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                    connectivity.getLinkProperties(network)?.interfaceName == interfaceName
            }) return
            check(SystemClock.elapsedRealtime() < deadline) { "系统隧道就绪超时" }
            Thread.sleep(TUN_READY_POLL_MS)
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        check(callback == null) { "网络监视器已启动" }
        this.listener = listener
        val observer = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = publish()
            override fun onLost(network: Network) = publish()
            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = publish()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
        }
        callback = observer
        try {
            connectivity.registerNetworkCallback(NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build(), observer)
            publish()
        } catch (error: Exception) {
            callback = null
            this.listener = null
            throw error
        }
    }

    private fun publish() {
        val network = physical()
        val properties = network?.let { connectivity.getLinkProperties(it) }
        val name = properties?.interfaceName
        val index = name?.let { NetworkInterface.getByName(it)?.index } ?: -1
        service?.setUnderlyingNetworks(network?.let { arrayOf(it) })
        listener?.updateDefaultInterface(name ?: "", index,
            network?.let { connectivity.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false } ?: false,
            false)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) = close()
    @Synchronized fun close() {
        this.listener = null
        val observer = callback
        callback = null
        observer?.let { connectivity.unregisterNetworkCallback(it) }
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val values = Collections.list(NetworkInterface.getNetworkInterfaces()).map { item ->
            val network = connectivity.allNetworks.firstOrNull { connectivity.getLinkProperties(it)?.interfaceName == item.name }
            val caps = network?.let { connectivity.getNetworkCapabilities(it) }
            CoreInterface().apply {
                index = item.index
                name = item.name
                mtu = item.mtu
                addresses = Strings(item.interfaceAddresses.map { "${it.address.hostAddress?.substringBefore('%')}/${it.networkPrefixLength}" })
                flags = (if (item.isUp) OsConstants.IFF_UP or OsConstants.IFF_RUNNING else 0) or
                    (if (item.isLoopback) OsConstants.IFF_LOOPBACK else 0) or
                    (if (item.isPointToPoint) OsConstants.IFF_POINTOPOINT else 0) or
                    (if (item.supportsMulticast()) OsConstants.IFF_MULTICAST else 0)
                type = when {
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> Libbox.InterfaceTypeWIFI
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> Libbox.InterfaceTypeCellular
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                setDNSServer(Strings(network?.let { connectivity.getLinkProperties(it)?.dnsServers?.map { address -> address.hostAddress ?: "" } } ?: emptyList()))
                metered = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
            }
        }.iterator()
        return object : NetworkInterfaceIterator {
            override fun hasNext() = values.hasNext()
            override fun next(): CoreInterface = values.next()
        }
    }

    override fun localDNSTransport(): LocalDNSTransport = object : LocalDNSTransport {
        override fun raw() = true
        override fun lookup(ctx: ExchangeContext, network: String, domain: String) =
            throw UnsupportedOperationException("仅支持原始 DNS 查询")
        override fun exchange(ctx: ExchangeContext, message: ByteArray) {
            val network = physical()
            if (network == null) { ctx.errnoCode(OsConstants.ENETUNREACH); return }
            val signal = CancellationSignal()
            ctx.onCancel(object : Func { override fun invoke() { signal.cancel() } })
            DnsResolver.getInstance().rawQuery(network, message, DnsResolver.FLAG_EMPTY,
                directExecutor, signal, object : DnsResolver.Callback<ByteArray> {
                    override fun onAnswer(answer: ByteArray, rcode: Int) { ctx.rawSuccess(answer) }
                    override fun onError(error: DnsResolver.DnsException) { ctx.errnoCode(OsConstants.EIO) }
                })
        }
    }

    override fun useProcFS() = false
    override fun findConnectionOwner(protocol: Int, source: String, sourcePort: Int, destination: String, destinationPort: Int): Int =
        connectivity.getConnectionOwnerUid(protocol, InetSocketAddress(source, sourcePort), InetSocketAddress(destination, destinationPort))
    override fun packageNameByUid(uid: Int) = context.packageManager.getPackagesForUid(uid)?.firstOrNull() ?: error("未找到应用")
    override fun uidByPackageName(packageName: String) = context.packageManager.getApplicationInfo(packageName, 0).uid
    override fun underNetworkExtension() = false
    override fun includeAllNetworks() = true
    override fun readWIFIState(): WIFIState? = null
    override fun systemCertificates(): StringIterator = Strings(emptyList())
    override fun clearDNSCache() { /* DnsResolver owns the platform cache. */ }
    override fun sendNotification(notification: Notification) { /* No user-configurable core notifications. */ }
    // Raw core messages may include credentials or subscription URLs. Public
    // lifecycle errors are produced by the service, never by forwarding logs.
    override fun writeLog(message: String) { }

    companion object {
        private const val TUN_READY_TIMEOUT_MS = 4000L
        private const val TUN_READY_POLL_MS = 20L
    }
}

internal class Strings(values: List<String>) : StringIterator {
    private val items = values.toList()
    private var index = 0
    override fun hasNext() = index < items.size
    override fun next(): String = items[index++]
    override fun len() = items.size - index
}
