package dev.rainlink.rainlink.core

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Bundle
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Runs only on the named QA AVD; the host restores its original radio settings. */
@RunWith(AndroidJUnit4::class)
class AndroidNetworkHandoverTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val gateway = CoreTestGateway()

    @Test fun wifiCellularAndOfflineRecoveryKeepTheOriginalTunnelAndManualStopWins() {
        val arguments = InstrumentationRegistry.getArguments()
        val proxyPort = arguments.getString("proxyPort")?.toInt() ?: error("Missing proxy fixture")
        val dnsPort = arguments.getString("dnsPort")?.toInt() ?: error("Missing DNS fixture")
        assertEquals("RainLink_QA", gateway.shell("getprop ro.boot.qemu.avd_name").trim())
        val observed = JSONArray()
        gateway.launch()
        gateway.rpc("disconnect")
        try {
            connectFixtureWifi()
            gateway.shell("svc data disable")
            waitFor("Wi-Fi as the only physical transport") {
                physical().isNotEmpty() && physical().all { hasTransport(it, NetworkCapabilities.TRANSPORT_WIFI) }
            }
            val cipher = gateway.rpc("protect", JSONObject().put("id", "qa-node")
                .put("username", "fixture-user").put("password", "fixture-password")).getString("cipher")
            val connected = gateway.connect(gateway.request(proxyPort, dnsPort, cipher))
            val session = connected.getString("sessionId")
            val interfaceName = connected.getString("tunInterface")
            val tunnel = connectivity.allNetworks.single { network ->
                hasTransport(network, NetworkCapabilities.TRANSPORT_VPN) &&
                    connectivity.getLinkProperties(network)?.interfaceName == interfaceName
            }

            fun record(stage: String, transport: Int?) {
                if (transport != null) {
                    waitFor("$stage physical transport isolation") {
                        physical().isNotEmpty() && physical().all { hasTransport(it, transport) }
                    }
                }
                val snapshot = gateway.rpc("snapshot")
                assertEquals(session, snapshot.getString("sessionId"))
                assertEquals(interfaceName, snapshot.getString("tunInterface"))
                assertTrue("The original system network must survive $stage",
                    hasTransport(tunnel, NetworkCapabilities.TRANSPORT_VPN))
                observed.put(JSONObject().put("stage", stage).put("sessionId", session)
                    .put("tunnelNetwork", tunnel.networkHandle).put("physicalNetworks", JSONArray(physical().map { it.networkHandle }))
                    .put("physicalCapabilities", JSONArray(physical().map { connectivity.getNetworkCapabilities(it).toString() })))
            }

            record("wifi", NetworkCapabilities.TRANSPORT_WIFI)
            assertTrue(gateway.shellRequest("198.51.100.42").contains(MARKER))
            gateway.shell("svc data enable")
            gateway.shell("svc wifi disable")
            waitFor("cellular after Wi-Fi disabled") {
                physical().none { hasTransport(it, NetworkCapabilities.TRANSPORT_WIFI) } &&
                    physical().any { hasTransport(it, NetworkCapabilities.TRANSPORT_CELLULAR) }
            }
            record("cellular", NetworkCapabilities.TRANSPORT_CELLULAR)
            assertTrue("A new request must use the cellular network",
                gateway.shellRequest("198.51.100.42").contains(MARKER))

            gateway.shell("svc data disable")
            waitFor("all physical networks disconnected") { physical().isEmpty() }
            record("offline", null)
            assertFalse(gateway.shellRequest("198.51.100.42", 1).contains(MARKER))
            connectFixtureWifi()
            waitFor("Wi-Fi restored") { physical().any { hasTransport(it, NetworkCapabilities.TRANSPORT_WIFI) } }
            record("wifi-restored", NetworkCapabilities.TRANSPORT_WIFI)
            assertTrue("Traffic must recover without reconnecting the tunnel",
                gateway.shellRequest("198.51.100.42").contains(MARKER))

            gateway.shell("svc wifi disable")
            waitFor("offline before manual stop") { physical().isEmpty() }
            gateway.rpc("disconnect")
            connectFixtureWifi()
            waitFor("Wi-Fi after manual stop") { physical().any { hasTransport(it, NetworkCapabilities.TRANSPORT_WIFI) } }
            Thread.sleep(1000)
            assertEquals("idle", gateway.rpc("snapshot").getString("phase"))
            assertFalse(gateway.rpc("restore").has("request"))
            assertFalse(connectivity.allNetworks.any { hasTransport(it, NetworkCapabilities.TRANSPORT_VPN) })
            val report = JSONObject().put("stages", observed).put("actualTransfers", 3)
                .put("sameSystemTunnelSurvived", true).put("manualStopPreventedLateReconnect", true)
                .put("transportEvidence", "only the stated physical transport is available during each actual independent-UID transfer")
            instrumentation.sendStatus(0, Bundle().apply { putString("rainlinkNetworkFlow", report.toString()) })
        } finally {
            try { gateway.rpc("disconnect") } finally {
                gateway.shell("svc wifi enable")
                gateway.shell("svc data enable")
            }
        }
    }

    private fun hasTransport(network: Network, transport: Int) =
        connectivity.getNetworkCapabilities(network)?.hasTransport(transport) == true

    private fun physical() = connectivity.allNetworks.filter {
        connectivity.getNetworkCapabilities(it)?.let { capabilities ->
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        } == true
    }

    private fun connectFixtureWifi() {
        gateway.shell("svc wifi enable")
        waitFor("Wi-Fi radio enabled") { gateway.shell("cmd wifi status").startsWith("Wifi is enabled") }
        // The AVD can disable auto-join after an unsuccessful public Internet
        // check. Explicitly select its virtual AP; fixtures remain host-local.
        gateway.shell("cmd wifi connect-network AndroidWifi open")
    }

    private fun waitFor(description: String, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (!predicate()) {
            check(SystemClock.elapsedRealtime() < deadline) {
                "Timed out waiting for $description; networks=" + connectivity.allNetworks.joinToString {
                    "$it:${connectivity.getNetworkCapabilities(it)}@${connectivity.getLinkProperties(it)?.interfaceName}"
                }
            }
            Thread.sleep(100)
        }
    }

    companion object { private const val MARKER = "RainLink Android tunnel fixture" }
}
