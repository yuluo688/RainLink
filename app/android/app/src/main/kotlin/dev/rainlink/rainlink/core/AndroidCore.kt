package dev.rainlink.rainlink.core

import android.content.Context
import android.app.Application
import android.content.Intent
import android.os.Handler
import android.os.Looper
import dev.rainlink.rainlink.notifications.AndroidNotifications
import dev.rainlink.core.libbox.Libbox
import dev.rainlink.core.libbox.SetupOptions
import dev.rainlink.core.mobile.Mobile
import dev.rainlink.core.mobile.DNSProbe
import dev.rainlink.core.mobile.Runtime as CoreRuntime
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

internal data class CoreReply(val value: String? = null, val code: String = "", val message: String = "")
internal typealias Reply = (CoreReply) -> Unit

/** Serializes lifecycle changes; only ciphertext is retained for UI recovery. */
internal object AndroidCore {
    private val worker = Executors.newSingleThreadExecutor()
    private val probes = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicLong()
    private val testGeneration = AtomicLong()
    private val dnsGeneration = AtomicLong()
    @Volatile private var dnsProbe: DNSProbe? = null
    private val testRuntimes = ConcurrentHashMap<String, CoreRuntime>()
    private lateinit var context: Application
    private val secrets by lazy { AndroidSecretStore() }
    private val logs by lazy { Mobile.newLogStore() }
    @Volatile private var ready = false
    @Volatile private var runtime: CoreRuntime? = null
    private var activeRequest: String? = null
    private var platform: AndroidPlatform? = null
    private var owner: RainlinkVpnService? = null
    private var ownerStartId = 0
    @Volatile private var starting = false
    @Volatile private var lastError = ""
    @Volatile private var pending: Pending? = null
    private data class Pending(val generation: Long, val request: String, val reply: Reply)

    @Synchronized
    fun initialize(application: Context) {
        if (ready) return
        context = application.applicationContext as Application
        AndroidNotifications.initialize(context)
        go.Seq.setContext(context)
        val directory = File(context.noBackupFilesDir, "core").apply { mkdirs() }
        val temporary = File(context.cacheDir, "core").apply { mkdirs() }
        Libbox.setup(SetupOptions().apply {
            basePath = directory.absolutePath
            workingPath = directory.absolutePath
            tempPath = temporary.absolutePath
            fixAndroidStack = true
        })
        ready = true
    }

    fun isConnecting() = starting

    fun request(method: String, raw: String, reply: Reply) {
        if (raw.length > 4 * 1024 * 1024) { deliver(reply, CoreReply(code = "invalid_request", message = "请求超过大小限制")); return }
        when (method) {
            "disconnect", "cancel" -> disconnect(reply)
            "cancelTests" -> {
                testGeneration.incrementAndGet()
                worker.execute {
                    guarded(reply, "cancel_failed", "停止测试失败") {
                        testRuntimes.values.forEach { it.close() }
                        JSONObject()
                    }
                }
            }
            "measure" -> measure(raw, reply)
            "testDns" -> testDns(raw, reply)
            "cancelDns" -> {
                dnsGeneration.incrementAndGet()
                dnsProbe?.cancel()
                deliver(reply, CoreReply(value = "{}"))
            }
            else -> worker.execute {
                guarded(reply, "native_failed", errorFor(method)) {
                    check(ready) { "原生核心尚未初始化" }
                    val input = JSONObject(raw)
                    when (method) {
                        "status" -> JSONObject().put("coreVersion", Libbox.version()).put("requiresTun", true)
                        "protect" -> JSONObject().put("cipher", secrets.protect(input.getString("id"), input))
                        "reveal" -> secrets.reveal(input.getString("id"), input.getString("cipher"))
                        "snapshot" -> runtime?.let { JSONObject(it.snapshot()) }
                            ?: JSONObject().put("phase", "idle").put("error", lastError)
                        "restore" -> runtime?.let {
                            val snapshot = JSONObject(it.snapshot())
                            val request = JSONObject(checkNotNull(activeRequest))
                            request.put("mode", snapshot.getString("mode"))
                            request.put("runtimeSettings", snapshot.getJSONObject("runtimeSettings"))
                            snapshot.put("request", request)
                        } ?: JSONObject().put("phase", "idle").put("error", lastError)
                        "mode" -> { active().setMode(input.getString("mode")); JSONObject() }
                        "probe" -> { active().probe(); JSONObject() }
                        "connections" -> JSONObject(active().readConnections(input.getString("sessionId"),
                            input.optString("snapshotId", ""), input.getInt("cursor")))
                        "closeConnections" -> {
                            active().closeConnections(input.getString("sessionId"), input.getString("connectionId"), input.getBoolean("all"))
                            JSONObject()
                        }
                        "logs" -> JSONObject(logs.read(input.optString("stream", ""), input.optLong("after", 0)))
                        "clearLogs" -> JSONObject(logs.clear())
                        "validateRules" -> { Mobile.validateRules(raw); JSONObject() }
                        "validate" -> {
                            val envelope = JSONObject(Mobile.compile(secrets.prepare(input), false))
                            Mobile.checkConfig(envelope.getString("configuration"))
                            JSONObject()
                        }
                        else -> throw IllegalArgumentException("不支持此命令")
                    }
                }
            }
        }
    }

    fun connect(raw: String, reply: Reply) {
        if (starting || runtime != null || pending != null) {
            deliver(reply, CoreReply(code = "busy", message = "已有连接操作正在进行")); return
        }
        val token = generation.incrementAndGet()
        starting = true
        lastError = ""
        pending = Pending(token, raw, reply)
        try {
            context.startForegroundService(Intent(context, RainlinkVpnService::class.java)
                .setAction(RainlinkVpnService.ACTION_CONNECT).putExtra(RainlinkVpnService.OPERATION_ID, token))
        } catch (error: Exception) {
            pending = null
            starting = false
            AndroidNotifications.connection("连接异常 · 无法启动后台网络服务")
            deliver(reply, CoreReply(code = "service_failed", message = "无法启动后台网络服务，请回到前台重试"))
        }
    }

    fun startPending(service: RainlinkVpnService, startId: Int, token: Long) {
        val work = pending
        if (work == null || work.generation != token) { service.finish(startId); return }
        pending = null
        worker.execute {
            var candidate: CoreRuntime? = null
            var adapter: AndroidPlatform? = null
            try {
                check(generation.get() == work.generation && starting)
                val input = JSONObject(work.request)
                require(!input.has("secrets")) { "连接请求不能包含明文凭据" }
                check(input.getBoolean("tun") && !input.getBoolean("systemProxy"))
                adapter = AndroidPlatform(context, service) { generation.get() == work.generation }
                owner = service
                ownerStartId = startId
                candidate = Mobile.newRuntimeWithLogs(secrets.prepare(input), adapter, true, logs)
                candidate.start()
                check(generation.get() == work.generation && RainlinkVpnService.current === service)
                val snapshot = JSONObject(candidate.snapshot())
                adapter.awaitTunnelReady(snapshot.getString("tunInterface"))
                check(generation.get() == work.generation && RainlinkVpnService.current === service)
                runtime = candidate
                activeRequest = work.request
                platform = adapter
                starting = false
                candidate.probe()
                service.connected(snapshot.getJSONObject("target").getString("name"))
                AndroidNotifications.connection("已连接")
                deliver(work.reply, CoreReply(value = snapshot.toString()))
            } catch (error: Exception) {
                var cleanupFailed = false
                try { candidate?.close() } catch (cleanup: Exception) { cleanupFailed = true }
                try { adapter?.close() } catch (cleanup: Exception) { cleanupFailed = true }
                try { service.releaseTunnel() } catch (cleanup: Exception) { cleanupFailed = true }
                runtime = if (cleanupFailed) candidate else null
                activeRequest = null
                platform = if (cleanupFailed) adapter else null
                owner = if (cleanupFailed) service else null
                starting = false
                val cancelled = generation.get() != work.generation
                lastError = when {
                    cleanupFailed -> "连接失败，网络资源未完全释放，请重试断开"
                    cancelled -> ""
                    else -> "网络服务未能启动，请检查系统授权、节点参数和端口占用"
                }
                if (!cleanupFailed) service.finish(startId)
                if (!cancelled) AndroidNotifications.connection("连接异常 · $lastError")
                deliver(work.reply, CoreReply(code = if (cancelled) "cancelled" else "connect_failed",
                    message = if (cancelled) "连接已取消" else lastError))
            }
        }
    }

    fun disconnect(reply: Reply) {
        generation.incrementAndGet()
        val waiting = pending
        pending = null
        waiting?.let { deliver(it.reply, CoreReply(code = "cancelled", message = "连接已取消")) }
        worker.execute {
            guarded(reply, "disconnect_failed", "停止网络服务失败，请重试断开") {
                stopOwned()
                lastError = ""
                JSONObject()
            }
        }
    }

    private fun stopOwned(notify: Boolean = true) {
        val wasConnected = runtime != null
        val service = owner ?: RainlinkVpnService.current
        val startId = if (owner != null) ownerStartId else service?.latestStartId ?: 0
        // The original TUN is closed even if libbox fails, so traffic is never
        // left routed into an abandoned descriptor after a stop request.
        var failure: Exception? = null
        try { runtime?.close() } catch (error: Exception) { failure = error }
        try { platform?.close() } catch (error: Exception) { failure = error }
        try { service?.releaseTunnel() } catch (error: Exception) { failure = error }
        if (failure == null) {
            runtime = null
            activeRequest = null
            platform = null
            owner = null
            if (notify && wasConnected) AndroidNotifications.connection("已断开")
            ownerStartId = 0
            starting = false
            service?.finish(startId)
        } else {
            lastError = "网络资源未完全释放，请重试断开"
            throw failure
        }
    }

    fun revoked(service: RainlinkVpnService) {
        generation.incrementAndGet()
        worker.execute {
            if (owner === service) {
                lastError = try {
                    stopOwned(notify = false)
                    "系统网络授权已撤销，连接已断开"
                } catch (error: Exception) {
                    "系统网络授权已撤销，网络资源未完全释放，请重试断开"
                }
                AndroidNotifications.connection(lastError)
            }
        }
    }

    fun serviceDestroyed(service: RainlinkVpnService) {
        worker.execute {
            if (owner === service) {
                generation.incrementAndGet()
                try { stopOwned() } catch (error: Exception) { lastError = "后台服务停止，网络资源释放失败" }
            }
        }
    }

    private fun measure(raw: String, reply: Reply) {
        val token = testGeneration.get()
        probes.execute {
            guarded(reply, "probe_failed", "节点测试失败，请检查认证和网络") {
                val input = JSONObject(raw)
                val id = input.getString("testId")
                input.remove("testId")
                val adapter = AndroidPlatform(context)
                var temporary: CoreRuntime? = null
                try {
                    check(testGeneration.get() == token)
                    temporary = Mobile.newRuntime(secrets.prepare(input), adapter, false)
                    testRuntimes[id] = temporary
                    check(testGeneration.get() == token)
                    temporary.start()
                    val latency = temporary.measure()
                    check(testGeneration.get() == token)
                    JSONObject().put("latency", latency)
                } finally {
                    testRuntimes.remove(id)
                    try { temporary?.close() } finally { adapter.close() }
                }
            }
        }
    }

    private fun testDns(raw: String, reply: Reply) {
        val token = dnsGeneration.incrementAndGet()
        dnsProbe?.cancel()
        probes.execute {
            guarded(reply, "dns_test_failed", "解析测试失败，请检查解析器、引导 DNS 和本机网络") {
                val adapter = AndroidPlatform(context)
                val settings = JSONObject(raw)
                if (settings.getString("dnsMode") == "system") {
                    val address = adapter.systemDnsAddress().substringBefore('%')
                    settings.put("dnsMode", "custom")
                    settings.put("resolver", "udp://${if (address.contains(':')) "[$address]" else address}:53")
                }
                val probe = Mobile.newDNSProbe(settings.toString(), adapter)
                dnsProbe = probe
                try {
                    check(dnsGeneration.get() == token)
                    val result = JSONObject(probe.run())
                    check(dnsGeneration.get() == token)
                    result
                } finally {
                    probe.cancel()
                    if (dnsProbe === probe) dnsProbe = null
                    adapter.close()
                }
            }
        }
    }

    private fun active() = runtime ?: error("请先连接节点")
    private fun errorFor(method: String) = when (method) {
        "protect" -> "凭据安全保存失败"
        "reveal" -> "凭据读取失败，请重新保存节点或导入订阅"
        "validate", "validateRules" -> "配置未通过核心校验，请检查协议和网络设置"
        "snapshot" -> "无法读取网络服务状态，请重试断开"
        "connections" -> "连接列表已失效或无法读取，请刷新"
        "closeConnections" -> "核心未确认关闭连接，请刷新列表"
        "logs", "clearLogs" -> "无法读取或清空核心日志，请重试"
        else -> "原生网络操作失败，请重试"
    }
    private fun guarded(reply: Reply, code: String, message: String, block: () -> JSONObject) {
        try { deliver(reply, CoreReply(value = block().toString())) }
        catch (error: Exception) { deliver(reply, CoreReply(code = code, message = message)) }
    }
    private fun deliver(reply: Reply, value: CoreReply) { main.post { reply(value) } }
}
