package dev.rainlink.rainlink.updates

import android.content.pm.PackageManager
import android.os.SystemClock
import android.os.Build
import android.view.WindowInsetsController
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.rainlink.rainlink.MainActivity
import dev.rainlink.rainlink.waitForOrdinaryAppReady
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Runs only on the disposable update AVD, with unpublished fixture APKs. */
@RunWith(AndroidJUnit4::class)
class AndroidUpdateInstallerTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val arguments = InstrumentationRegistry.getArguments()
    private val candidateName = "RainLink-0.1.0+5-android-universal.apk"

    private fun assertIsolated() {
        // Do not claim UiAutomation: the external harness owns it while
        // inspecting actual system consent windows in this same test.
        val process = Runtime.getRuntime().exec(arrayOf("/system/bin/getprop", "ro.boot.qemu.avd_name"))
        assertTrue(process.waitFor(5, TimeUnit.SECONDS))
        val value = process.inputStream.bufferedReader().use { it.readText().trim() }
        assertEquals("Refusing to mutate any user device", "RainLink_Update_QA", value)
    }

    private class Result : MethodChannel.Result {
        val finished = CountDownLatch(1)
        var code = ""
        var value: Any? = null
        override fun success(result: Any?) { value = result; finished.countDown() }
        override fun error(errorCode: String, message: String?, details: Any?) { code = errorCode; finished.countDown() }
        override fun notImplemented() { code = "not_implemented"; finished.countDown() }
        fun await() { assertTrue("Native update request timed out", finished.await(60, TimeUnit.SECONDS)) }
    }

    private fun payload(name: String = candidateName, code: Int = 5, digest: String? = null): Map<String, Any> {
        val file = File(context.cacheDir, "updates/download-fixture/$name")
        assertTrue("Fixture APK was not provisioned", file.isFile)
        val sha = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val bytes = ByteArray(64 * 1024)
            while (true) { val count = input.read(bytes); if (count < 0) break; sha.update(bytes, 0, count) }
        }
        return mapOf("id" to UUID.randomUUID().toString().replace("-", ""), "path" to file.path,
            "bytes" to file.length(), "sha256" to (digest ?: sha.digest().joinToString("") { "%02x".format(it) }),
            "versionName" to "0.1.0", "versionCode" to code)
    }

    private fun call(scenario: ActivityScenario<MainActivity>, method: String, payload: Any? = null): Result {
        val result = Result()
        scenario.onActivity { it.updateInstaller!!.handle(MethodCall(method, payload), result) }
        return result
    }

    @Test fun validatesActualPackageAndPrivateCopyBeforeConsent() {
        assertIsolated()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            waitForOrdinaryAppReady()
            val payload = payload()
            val ready = call(scenario, "prepare", payload).also { it.await() }
            assertEquals("", ready.code)
            assertEquals(payload["id"], ready.value)
            val staged = File(context.cacheDir, "updates/install/${payload["id"]}.apk")
            assertEquals(File(payload["path"] as String).length(), staged.length())
            val busy = call(scenario, "prepare", payload()).also { it.await() }
            assertEquals("busy", busy.code)
            // A mutation after preparation must be caught before opening settings.
            staged.outputStream().use { it.write(byteArrayOf(0, 1, 2)) }
            val rejected = call(scenario, "commit", mapOf("id" to payload["id"])).also { it.await() }
            assertEquals("invalid_package", rejected.code)
            assertFalse(staged.exists())
            val fresh = payload()
            assertEquals("", call(scenario, "prepare", fresh).also { it.await() }.code)
            assertEquals("", call(scenario, "abort", mapOf("id" to fresh["id"])).also { it.await() }.code)
            assertFalse(File(context.cacheDir, "updates/install/${fresh["id"]}.apk").exists())
        }
    }

    @Test fun rejectsWrongDigestVersionPackageSignatureAndPath() {
        assertIsolated()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            waitForOrdinaryAppReady()
            val bad = listOf(
                payload(digest = "0".repeat(64)),
                payload("RainLink-0.1.0+4-android-universal.apk", 4),
                payload("RainLink-0.1.0+6-android-universal.apk", 6),
                payload().toMutableMap().apply { put("path", File(context.filesDir, "outside.apk").path) },
                payload().toMutableMap().apply { put("versionCode", 5.5) },
            )
            for (value in bad) {
                assertEquals("invalid_package", call(scenario, "prepare", value).also { it.await() }.code)
            }
            // These variants are separately staged under the expected filename.
            for (variant in listOf("wrong-package.apk", "wrong-signer.apk")) {
                val source = File(context.cacheDir, "update-fixtures/$variant")
                assertTrue(source.isFile)
                val target = File(context.cacheDir, "updates/download-rejected/$candidateName")
                target.parentFile!!.mkdirs()
                source.copyTo(target, overwrite = true)
                val value = payload().toMutableMap().apply {
                    put("path", target.path)
                    put("bytes", target.length())
                    val sha = MessageDigest.getInstance("SHA-256")
                    target.inputStream().use { input -> val buffer = ByteArray(65536)
                        while (true) { val n = input.read(buffer); if (n < 0) break; sha.update(buffer, 0, n) } }
                    put("sha256", sha.digest().joinToString("") { "%02x".format(it) })
                }
                assertEquals("invalid_package", call(scenario, "prepare", value).also { it.await() }.code)
                assertTrue(target.delete())
            }
        }
    }

    @Test fun cancelledPreparationDoesNotLeaveAPackage() {
        assertIsolated()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            waitForOrdinaryAppReady()
            val value = payload()
            val result = Result()
            val cancelled = Result()
            scenario.onActivity {
                it.updateInstaller!!.handle(MethodCall("prepare", value), result)
                it.updateInstaller!!.handle(MethodCall("cancelPrepare", mapOf("id" to value["id"])), cancelled)
            }
            cancelled.await(); result.await()
            assertEquals("cancelled", result.code)
            assertFalse(File(context.cacheDir, "updates/install/${value["id"]}.apk").exists())
        }
    }

    @Test fun systemConsent() {
        assertIsolated()
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        try {
            waitForOrdinaryAppReady()
            if (arguments.getString("expectedLightSystemBars") == "true") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    scenario.onActivity { activity ->
                        val appearance = activity.window.insetsController?.systemBarsAppearance ?: 0
                        assertTrue("Light theme must use dark status bar icons",
                            appearance and WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS != 0)
                        assertTrue("Light theme must use a dark navigation indicator",
                            appearance and WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS != 0)
                    }
                } else fail("This QA stage requires API 30 or newer")
            }
            val value = payload()
            assertEquals("", call(scenario, "prepare", value).also { it.await() }.code)
            val installing = call(scenario, "commit", mapOf("id" to value["id"]))
            File(context.cacheDir, "update-consent-ready").writeText("ready")
            // The external harness drives actual system consent. Successful
            // replacement ends this old process; it verifies PackageManager and
            // the next normal application startup instead of trusting this RPC.
            installing.await()
            val expected = arguments.getString("expectedOutcome") ?: "cancelled"
            assertEquals(expected, installing.code)
            assertFalse(File(context.cacheDir, "updates/install/${value["id"]}.apk").exists())
        } finally { scenario.close() }
    }
}
