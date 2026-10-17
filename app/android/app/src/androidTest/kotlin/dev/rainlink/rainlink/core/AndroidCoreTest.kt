package dev.rainlink.rainlink.core

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.rainlink.rainlink.notifications.AndroidNotifications
import dev.rainlink.rainlink.notifications.waitForNotification
import dev.rainlink.rainlink.notifications.waitForNoNotification
import dev.rainlink.core.libbox.Libbox
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.io.File
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean

@RunWith(AndroidJUnit4::class)
class AndroidCoreTest {
    private val gateway = CoreTestGateway()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val arguments = InstrumentationRegistry.getArguments()

    @Test fun credentialsAreRandomAuthenticatedAndBoundToIdentity() {
        val store = AndroidSecretStore()
        val credentials = JSONObject().put("username", "fixture-user").put("password", "fixture-password").put("obfsPassword", "fixture-obfs")
        val first = store.protect("fixture", credentials)
        val second = store.protect("fixture", credentials)
        assertNotEquals(first, second)
        assertFalse(first.contains("fixture-password"))
        assertEquals("fixture-password", AndroidSecretStore().reveal("fixture", first).getString("password"))
        assertThrows(Exception::class.java) { store.reveal("different", first) }
        val position = first.length / 2
        val corrupted = first.substring(0, position) + (if (first[position] == 'A') 'B' else 'A') + first.substring(position + 1)
        assertThrows(Exception::class.java) { store.reveal("fixture", corrupted) }
        assertThrows(Exception::class.java) { store.protect("fixture", JSONObject().put("password", "x".repeat(4097))) }
    }

    @Test fun tunnelCarriesIPv4IPv6AndDNSAndSurvivesBackground() {
        val proxyPort = arguments.getString("proxyPort")?.toInt() ?: error("proxyPort fixture argument is required")
        val dnsPort = arguments.getString("dnsPort")?.toInt() ?: error("dnsPort fixture argument is required")
        gateway.launch()
        Libbox.redirectStderr(File(context.cacheDir, "native-qa-stderr.log").absolutePath)
        assertNull("The QA runner must grant the system tunnel app-op", VpnService.prepare(context))
        gateway.rpc("disconnect")
        val cipher = gateway.rpc("protect", JSONObject().put("id", "qa-node").put("username", "fixture-user").put("password", "fixture-password")).getString("cipher")
        val request = gateway.request(proxyPort, dnsPort, cipher)
        try {
            val snapshot = gateway.connect(request)
            assertTrue(snapshot.getBoolean("tun"))
            assertFalse(snapshot.getBoolean("systemProxy"))
            val interfaceName = snapshot.getString("tunInterface")
            assertTrue("The actual TUN interface must exist", java.net.NetworkInterface.getByName(interfaceName)?.isUp == true)
            assertFalse(snapshot.toString().contains(cipher))
            val session = snapshot.getString("sessionId")
            val ipv4 = gateway.shellRequest("198.51.100.42")
            assertTrue("IPv4 fixture was not reached: ${ipv4.take(300)}\n${gateway.rpc("snapshot")}\n${gateway.rpc("logs")}", ipv4.contains(MARKER))
            assertTrue(gateway.shellRequest("2001:db8::42").contains(MARKER))
            val dns = gateway.rpc("testDns", request.getJSONObject("runtimeSettings"))
            assertEquals("198.51.100.42", dns.getJSONArray("addresses").getString(0))
            assertTrue(gateway.shellRequest("rainlink.test").contains(MARKER))
            val observed = gateway.rpc("snapshot")
            assertTrue(observed.getJSONObject("telemetry").getLong("downloadTotal") > 0)
            gateway.rpc("mode", JSONObject().put("mode", "direct"))
            assertEquals("direct", gateway.rpc("snapshot").getString("mode"))
            assertFalse(gateway.shellRequest("198.51.100.42", 1).contains(MARKER))
            gateway.rpc("mode", JSONObject().put("mode", "rule"))
            assertTrue(gateway.shellRequest("198.51.100.42").contains(MARKER))
            gateway.shell("input keyevent KEYCODE_HOME")
            assertTrue(gateway.shellRequest("198.51.100.42").contains(MARKER))
            assertTrue(gateway.shell("dumpsys activity services ${context.packageName}").contains("isForeground=true"))
            gateway.launch()
            gateway.recreateActivity()
            assertEquals(session, gateway.rpc("snapshot").getString("sessionId"))
            val recovered = gateway.rpc("restore")
            assertEquals(session, recovered.getString("sessionId"))
            val original = recovered.getJSONObject("request")
            assertFalse(original.has("secrets"))
            assertFalse(original.toString().contains("fixture-password"))
            assertEquals(cipher, original.getJSONObject("node").getString("credential"))
            assertEquals(7, original.getJSONObject("routing").getInt("revision"))
            assertEquals("rule", original.getString("mode"))
            val logs = gateway.rpc("logs").toString()
            assertFalse(logs.contains("fixture-password"))
            assertFalse(logs.contains(cipher))
            gateway.rpc("disconnect")
            val restarted = gateway.connect(original)
            assertNotEquals(session, restarted.getString("sessionId"))
            assertTrue(gateway.shellRequest("198.51.100.42").contains(MARKER))
            Libbox.setMemoryLimit(true)
            repeat(12) {
                assertTrue(gateway.shellRequest("198.51.100.42").contains(MARKER))
                assertEquals(restarted.getString("sessionId"), gateway.rpc("snapshot").getString("sessionId"))
            }
        } finally {
            try { gateway.rpc("disconnect") } finally { Libbox.setMemoryLimit(false) }
        }
        assertEquals("idle", gateway.rpc("snapshot").getString("phase"))
        assertFalse(gateway.rpc("restore").has("request"))
        assertFalse(gateway.shellRequest("198.51.100.42", 1).contains(MARKER))
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        assertFalse(connectivity.allNetworks.any { connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true })
    }

    @Test fun cancelCannotLeaveALateTunnelAndInvalidCredentialsDoNotConnect() {
        val proxyPort = arguments.getString("proxyPort")?.toInt() ?: error("proxyPort fixture argument is required")
        val dnsPort = arguments.getString("dnsPort")?.toInt() ?: error("dnsPort fixture argument is required")
        gateway.launch()
        gateway.rpc("disconnect")
        val cipher = gateway.rpc("protect", JSONObject().put("id", "qa-node").put("password", "fixture-password")).getString("cipher")
        val request = gateway.request(proxyPort, dnsPort, cipher)
        val connected = CountDownLatch(1)
        instrumentation.runOnMainSync { AndroidCore.connect(request.toString()) { connected.countDown() } }
        gateway.rpc("cancel")
        assertTrue(connected.await(20, TimeUnit.SECONDS))
        assertEquals("idle", gateway.rpc("snapshot").getString("phase"))
        val wrongId = gateway.request(proxyPort, dnsPort, cipher)
        wrongId.getJSONObject("node").put("id", "different-node")
        assertThrows(AssertionError::class.java) { gateway.connect(wrongId) }
        assertEquals("idle", gateway.rpc("snapshot").getString("phase"))
        gateway.rpc("disconnect")
    }

    @Test fun telemetryClosesRealStreamsAndKeepsSanitizedLogsAfterDisconnect() {
        val proxyPort = arguments.getString("proxyPort")?.toInt() ?: error("proxyPort fixture argument is required")
        val dnsPort = arguments.getString("dnsPort")?.toInt() ?: error("dnsPort fixture argument is required")
        gateway.launch()
        gateway.rpc("disconnect")
        val initial = gateway.rpc("clearLogs")
        assertEquals(0, initial.getJSONArray("entries").length())
        val cipher = gateway.rpc("protect", JSONObject().put("id", "qa-node").put("username", "fixture-user").put("password", "fixture-password")).getString("cipher")
        val held = mutableListOf<HeldRequest>()
        try {
            AndroidNotifications.configure(true, false)
            val session = gateway.connect(gateway.request(proxyPort, dnsPort, cipher)).getString("sessionId")
            waitForNotification(AndroidNotifications.CONNECTION_ID, "已连接")
            AndroidNotifications.configure(false, false)
            waitForNoNotification(AndroidNotifications.CONNECTION_ID)
            waitForNotification(RainlinkVpnService.NOTIFICATION_ID)
            AndroidNotifications.configure(true, false)
            held += HeldRequest()
            held[0].assertStarted()
            val first = waitForConnections(session, 1)
            val id = first.getJSONObject(0).getString("id")
            val close = JSONObject().put("sessionId", session).put("connectionId", id).put("all", false)
            assertThrows(AssertionError::class.java) { gateway.rpc("closeConnections", JSONObject(close.toString()).put("sessionId", "stale-session")) }
            assertThrows(AssertionError::class.java) { gateway.rpc("closeConnections", JSONObject(close.toString()).put("connectionId", "../configs")) }
            assertFalse("A rejected close must keep the actual transfer alive", held[0].finished.await(100, TimeUnit.MILLISECONDS))
            gateway.rpc("closeConnections", close)
            held[0].assertClosed()
            held += HeldRequest()
            held += HeldRequest()
            held.drop(1).forEach { it.assertStarted() }
            waitForConnections(session, 2)
            gateway.rpc("closeConnections", JSONObject().put("sessionId", session).put("connectionId", "").put("all", true))
            held.drop(1).forEach { it.assertClosed() }
            assertTrue("Closing request streams must keep the tunnel usable", gateway.shellRequest("198.51.100.42").contains(MARKER))
            gateway.rpc("disconnect")
            waitForNotification(AndroidNotifications.CONNECTION_ID, "已断开")
            var batch = gateway.rpc("logs")
            assertEquals(initial.getString("stream"), batch.getString("stream"))
            var count = 0
            do {
                count += batch.getJSONArray("entries").length()
                val text = batch.toString()
                assertFalse(text.contains("fixture-password"))
                assertFalse(text.contains("fixture-user"))
                assertFalse(text.contains(cipher))
                val more = batch.getBoolean("more")
                if (more) batch = gateway.rpc("logs", JSONObject().put("stream", batch.getString("stream")).put("after", batch.getLong("cursor")))
            } while (more)
            assertTrue("No actual core log events were captured", count > 0)
            val cleared = gateway.rpc("clearLogs")
            assertEquals(initial.getString("stream"), cleared.getString("stream"))
            val after = gateway.rpc("logs", JSONObject().put("stream", cleared.getString("stream")).put("after", cleared.getLong("cursor")))
            assertEquals(0, after.getJSONArray("entries").length())
        } finally {
            try { gateway.rpc("disconnect") } finally {
                held.forEach { it.close() }
                AndroidNotifications.configure(false, false)
            }
        }
    }

    @Test fun startupPortConflictReleasesResourcesAndAllowsReconnect() {
        val proxyPort = arguments.getString("proxyPort")?.toInt() ?: error("proxyPort fixture argument is required")
        val dnsPort = arguments.getString("dnsPort")?.toInt() ?: error("dnsPort fixture argument is required")
        gateway.launch()
        gateway.rpc("disconnect")
        val cipher = gateway.rpc("protect", JSONObject().put("id", "qa-node").put("username", "fixture-user").put("password", "fixture-password")).getString("cipher")
        repeat(3) { round ->
            gateway.rpc("clearLogs")
            try {
                // Fail inside libbox.Start, after configuration has passed. The
                // core closes itself before RainLink's cleanup closes it again.
                ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { occupied ->
                    val conflicting = gateway.request(proxyPort, dnsPort, cipher)
                    conflicting.getJSONObject("runtimeSettings").put("proxyPort", occupied.localPort)
                    val reply = gateway.connectReply(conflicting)
                    assertEquals("connect_failed", reply.code)
                    assertEquals("idle", gateway.rpc("snapshot").getString("phase"))
                    assertFalse(gateway.rpc("restore").has("request"))
                    gateway.rpc("disconnect")
                }
                val connected = gateway.connect(gateway.request(proxyPort, dnsPort, cipher))
                assertTrue(connected.getBoolean("tun"))
                val connectivity = context.getSystemService(ConnectivityManager::class.java)
                val visibleTunnel = connectivity.allNetworks.any { network ->
                    connectivity.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                        connectivity.getLinkProperties(network)?.interfaceName == connected.getString("tunInterface")
                }
                assertTrue("Connection succeeded before Android registered its TUN, round=$round", visibleTunnel)
                val response = gateway.shellRequest("198.51.100.42", port = 18081)
                assertTrue("The core did not recover after a failed start, round=$round network=$visibleTunnel: ${response.take(300)}\n${gateway.rpc("snapshot")}\n${gateway.rpc("logs")}", response.contains(MARKER))
            } finally {
                gateway.rpc("disconnect")
            }
        }
        assertEquals("idle", gateway.rpc("snapshot").getString("phase"))
    }

    private fun waitForConnections(session: String, count: Int): JSONArray {
        var observed: JSONObject? = null
        repeat(40) {
            val page = gateway.rpc("connections", JSONObject().put("sessionId", session).put("cursor", 0))
            observed = page
            val entries = page.getJSONArray("entries")
            val matches = JSONArray()
            for (index in 0 until entries.length()) {
                val entry = entries.getJSONObject(index)
                if (entry.getString("destination") in listOf("198.51.100.42:18080", "rainlink.test:18080")) {
                    assertEquals("Android 隔离测试", entry.getString("outbound"))
                    assertFalse(entry.getBoolean("direct"))
                    matches.put(entry)
                }
            }
            if (matches.length() >= count) return matches
            Thread.sleep(100)
        }
        error("Expected held connections were missing from the actual core: $observed")
    }

    private inner class HeldRequest : AutoCloseable {
        val finished = CountDownLatch(1)
        private val received = CountDownLatch(1)
        private val body = AtomicReference<String>()
        private val failure = AtomicReference<Exception>()
        private val closing = AtomicBoolean()
        private val input = ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(
            "sh /data/local/tmp/rainlink-qa-request.sh 198.51.100.42 20 /hold"))
        private val reader = Thread {
            try {
                body.set(input.bufferedReader().use { stream ->
                    val text = StringBuilder()
                    val buffer = CharArray(2048)
                    while (true) {
                        val length = stream.read(buffer)
                        if (length < 0) break
                        text.append(buffer, 0, length)
                        if (text.contains(MARKER)) received.countDown()
                    }
                    text.toString()
                })
            } catch (error: Exception) {
                // Disposing this helper intentionally interrupts its pipe read.
                if (!closing.get() || error !is IOException) failure.set(error)
            }
            finally { finished.countDown() }
        }.apply { start() }

        fun assertStarted() {
            assertTrue("Held target did not receive the actual transfer", received.await(10, TimeUnit.SECONDS))
        }

        fun assertClosed() {
            assertTrue("Core close did not terminate the actual TCP stream", finished.await(5, TimeUnit.SECONDS))
            assertNull("Held stream reader failed", failure.get())
            assertTrue("Held target never received the authenticated transfer", body.get()?.contains(MARKER) == true)
        }

        override fun close() {
            closing.set(true)
            input.close()
            reader.join(1000)
            assertFalse("Held stream reader leaked after cleanup", reader.isAlive)
            failure.get()?.let { throw it }
        }
    }

    companion object { private const val MARKER = "RainLink Android tunnel fixture" }
}
