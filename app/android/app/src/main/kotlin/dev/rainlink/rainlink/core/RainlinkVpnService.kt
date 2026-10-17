package dev.rainlink.rainlink.core

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Handler
import android.os.Looper
import dev.rainlink.core.libbox.RoutePrefixIterator
import dev.rainlink.core.libbox.TunOptions
import dev.rainlink.rainlink.MainActivity
import dev.rainlink.rainlink.R

/** The system, rather than a Flutter page, owns the network connection. */
class RainlinkVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null
    @Volatile internal var latestStartId: Int = 0
        private set

    override fun onCreate() {
        super.onCreate()
        current = this
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(NotificationChannel(CHANNEL, "网络连接", NotificationManager.IMPORTANCE_LOW))
    }

    private fun enterForeground() {
        val notification = notification("正在连接…")
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        when (intent?.action) {
            ACTION_CONNECT -> {
                // A new foreground-service request may reuse an instance whose
                // preceding connection already called stopForeground().
                enterForeground()
                AndroidCore.startPending(this, startId, intent.getLongExtra(OPERATION_ID, -1))
            }
            ACTION_DISCONNECT -> AndroidCore.disconnect { }
            else -> stopSelf()
        }
        // OS process death must never resurrect a stale connection or secret.
        return START_NOT_STICKY
    }

    internal fun establishTunnel(options: TunOptions): Int {
        check(current === this && AndroidCore.isConnecting()) { "连接已取消" }
        check(tunnel == null) { "隧道已经建立" }
        check(prepare(this) == null) { "系统网络授权已撤销" }
        val builder = Builder().setSession("RainLink").setMtu(options.mtu)
            .setConfigureIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        fun addresses(iterator: RoutePrefixIterator) {
            while (iterator.hasNext()) {
                val prefix = iterator.next()
                builder.addAddress(prefix.address(), prefix.prefix())
            }
        }
        fun routes(iterator: RoutePrefixIterator) {
            while (iterator.hasNext()) {
                val prefix = iterator.next()
                builder.addRoute(prefix.address(), prefix.prefix())
            }
        }
        addresses(options.inet4Address)
        addresses(options.inet6Address)
        builder.addDnsServer(options.dnsServerAddress.value)
        routes(options.inet4RouteRange)
        routes(options.inet6RouteRange)
        // Flutter subscription fetching must avoid a dependency on its own
        // active proxy. Core socket protection remains mandatory as well.
        builder.addDisallowedApplication(packageName)
        val descriptor = builder.establish() ?: error("系统未创建网络隧道")
        tunnel = descriptor
        return descriptor.fd
    }

    internal fun connected(name: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("已连接 · $name"))
    }

    internal fun releaseTunnel() {
        val descriptor = tunnel
        tunnel = null
        descriptor?.close()
    }

    internal fun finish(startId: Int) {
        Handler(Looper.getMainLooper()).post {
            // An old operation must not stop a newer start on the same service.
            if (latestStartId == startId) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelfResult(startId)
            }
        }
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, RainlinkVpnService::class.java).setAction(ACTION_DISCONNECT), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_connection)
            .setContentTitle("RainLink")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(null, "断开", stop).build())
            .build()
    }

    override fun onRevoke() {
        AndroidCore.revoked(this)
        super.onRevoke()
    }

    override fun onDestroy() {
        if (current === this) current = null
        AndroidCore.serviceDestroyed(this)
        super.onDestroy()
    }

    companion object {
        @Volatile internal var current: RainlinkVpnService? = null
            private set
        internal const val ACTION_CONNECT = "dev.rainlink.CONNECT"
        internal const val OPERATION_ID = "operationId"
        private const val ACTION_DISCONNECT = "dev.rainlink.DISCONNECT"
        private const val CHANNEL = "rainlink_connection"
        internal const val NOTIFICATION_ID = 1042
    }
}
