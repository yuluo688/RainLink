package dev.rainlink.rainlink.core

import android.content.Intent
import android.os.ParcelFileDescriptor
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import dev.rainlink.rainlink.MainActivity
import dev.rainlink.rainlink.waitForOrdinaryAppReady
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Shared real-core bridge and shell client for isolated native QA cases. */
internal class CoreTestGateway {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    fun request(proxyPort: Int, dnsPort: Int, cipher: String): JSONObject = JSONObject()
        .put("node", JSONObject().put("id", "qa-node").put("name", "Android 隔离测试")
            .put("revision", 1).put("protocol", "http").put("server", "10.0.2.2")
            .put("port", proxyPort).put("tls", false).put("credential", cipher).put("options", JSONObject()))
        .put("mode", "global").put("tun", true).put("systemProxy", false)
        .put("runtimeSettings", JSONObject().put("proxyPort", 0).put("dnsMode", "custom")
            .put("resolver", "udp://10.0.2.2:$dnsPort").put("bootstrapDns", "10.0.2.2")
            .put("ipv6", true).put("logLevel", "info").put("advanced", ""))
        .put("routing", JSONObject().put("revision", 7).put("rules", JSONArray().put(
            JSONObject().put("id", "final").put("type", "MATCH").put("value", "").put("target", "proxy").put("enabled", true)))
            .put("outbounds", JSONArray()))

    fun launch() {
        instrumentation.runOnMainSync {
            context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            AndroidCore.initialize(context)
        }
        instrumentation.waitForIdleSync()
        waitForOrdinaryAppReady()
    }

    fun recreateActivity() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var original: MainActivity
            scenario.onActivity { original = it }
            scenario.recreate()
            lateinit var recreated: MainActivity
            scenario.onActivity { recreated = it }
            waitForOrdinaryAppReady(recreated)
            scenario.onActivity { assertNotSame("Activity was not recreated", original, it) }
        }
    }

    fun connect(request: JSONObject): JSONObject {
        val reply = connectReply(request)
        assertEquals(reply.message, "", reply.code)
        return JSONObject(reply.value ?: error("Missing native snapshot"))
    }

    fun connectReply(request: JSONObject): CoreReply {
        val finished = CountDownLatch(1)
        var response: CoreReply? = null
        instrumentation.runOnMainSync { AndroidCore.connect(request.toString()) { response = it; finished.countDown() } }
        assertTrue("Native connect timed out", finished.await(30, TimeUnit.SECONDS))
        return response ?: error("Missing native result")
    }

    fun rpc(method: String, request: JSONObject = JSONObject()): JSONObject {
        val finished = CountDownLatch(1)
        var response: CoreReply? = null
        AndroidCore.request(method, request.toString()) { response = it; finished.countDown() }
        assertTrue("Native $method timed out", finished.await(30, TimeUnit.SECONDS))
        val reply = response ?: error("Missing native result")
        assertEquals(reply.message, "", reply.code)
        return JSONObject(reply.value ?: error("Missing native result"))
    }

    fun shell(command: String): String = ParcelFileDescriptor.AutoCloseInputStream(
        instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use { it.readText() }

    fun shellRequest(address: String, timeout: Int = 5, port: Int = 18080): String = shell(
        "sh /data/local/tmp/rainlink-qa-request.sh $address $timeout /probe $port")

}
