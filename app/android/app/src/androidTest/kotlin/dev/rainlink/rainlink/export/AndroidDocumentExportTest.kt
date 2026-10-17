package dev.rainlink.rainlink.export

import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AndroidDocumentExportTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun systemPickerSavesExactBytesAndUserCancellationReturnsNull() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var activity: MainActivity
            scenario.onActivity { activity = it }
            waitForOrdinaryAppReady(activity)
            val fixture = fixture()
            var saved: Uri? = null
            try {
                val result = Result()
                scenario.onActivity { it.documentExporter!!.handle(MethodCall("saveDocument", fixture.arguments), result) }
                val save = waitForSaveButton(result)
                assertTrue("The system save button could not be clicked", save.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                result.await()
                assertEquals(result.message, "", result.code)
                val uri = Uri.parse(result.value as String)
                saved = uri
                assertEquals("content", uri.scheme)
                assertArrayEquals(fixture.content.toByteArray(Charsets.UTF_8),
                    context.contentResolver.openInputStream(uri)!!.use { it.readBytes() })
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)!!.use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals(fixture.name, cursor.getString(0))
                }
                val cancelled = Result()
                scenario.onActivity { it.documentExporter!!.handle(MethodCall("saveDocument", fixture.arguments), cancelled) }
                waitForSaveButton(cancelled)
                instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
                cancelled.await()
                assertEquals("", cancelled.code)
                assertNull(cancelled.value)
            } finally {
                saved?.let { uri ->
                    // This is the exact fresh document created by this test.
                    assertTrue(DocumentsContract.deleteDocument(context.contentResolver, uri))
                }
                assertTrue(fixture.directory.deleteRecursively())
            }
        }
    }

    @Test fun invalidSourcesBusyStateAndActivityDisposalCannotReportSuccess() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var activity: MainActivity
            scenario.onActivity { activity = it }
            waitForOrdinaryAppReady(activity)
            val fixture = fixture()
            try {
                for (override in listOf(
                    mapOf("sourcePath" to File(context.filesDir, "private.txt").path),
                    mapOf("suggestedName" to "../private.csv"),
                    mapOf("mimeType" to "application/octet-stream"),
                    mapOf("requestId" to "../invalid"),
                    mapOf("sourcePath" to 17),
                )) {
                    val rejected = Result()
                    scenario.onActivity { it.documentExporter!!.handle(MethodCall("saveDocument", fixture.arguments + override), rejected) }
                    rejected.await()
                    assertEquals("invalid_request", rejected.code)
                }
                val pending = Result()
                scenario.onActivity { it.documentExporter!!.handle(MethodCall("saveDocument", fixture.arguments), pending) }
                waitForSaveButton(pending)
                val busy = Result()
                scenario.onActivity { it.documentExporter!!.handle(MethodCall("saveDocument", fixture.arguments), busy) }
                busy.await()
                assertEquals("busy", busy.code)
                val unrelatedCancel = Result()
                scenario.onActivity { it.documentExporter!!.handle(MethodCall("cancelExport", mapOf("requestId" to "document-other")), unrelatedCancel) }
                unrelatedCancel.await()
                assertFalse("An unrelated cancellation ended the pending save", pending.finished.await(100, TimeUnit.MILLISECONDS))
                // The system picker leaves this activity STOPPED. Close it in
                // that state instead of forcing a RESUMED recreation behind it.
                scenario.close()
                pending.await()
                assertEquals("cancelled", pending.code)
                assertNull(pending.value)
            } finally {
                assertTrue(fixture.directory.deleteRecursively())
            }
        }
    }

    private data class Fixture(val directory: File, val name: String, val content: String, val arguments: Map<String, Any>)
    private fun fixture(): Fixture {
        val id = "document-qa-${System.nanoTime()}"
        val directory = File(context.cacheDir, "rainlink-exports/$id").apply { check(mkdirs()) }
        val content = "\uFEFF\"日期\",\"下载字节\"\r\n\"2026-10-17\",\"100\"\r\n"
        val source = File(directory, "content").apply { writeText(content, Charsets.UTF_8) }
        val name = "RainLink-QA-${System.nanoTime()}.csv"
        return Fixture(directory, name, content, mapOf("requestId" to id, "sourcePath" to source.path,
            "suggestedName" to name, "mimeType" to "text/csv"))
    }

    private fun waitForSaveButton(result: Result): AccessibilityNodeInfo {
        val automation = instrumentation.uiAutomation
        val info = automation.serviceInfo
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        automation.serviceInfo = info
        val deadline = SystemClock.uptimeMillis() + PICKER_TIMEOUT_MS
        var packages = emptySet<String>()
        while (SystemClock.uptimeMillis() < deadline) {
            assertFalse("Save ended before the system picker opened: ${result.code} ${result.message}",
                result.finished.count == 0L)
            // During a transition the interactive-window list can lag behind
            // the active root; the filename keyboard can also own that root.
            val roots = listOfNotNull(automation.rootInActiveWindow) +
                automation.windows.mapNotNull { it.root }
            packages = roots.map { it.packageName.toString() }.toSet()
            for (root in roots) {
                if (root.packageName?.contains("documentsui") == true) {
                    findSave(root)?.let { return it }
                }
            }
            Thread.sleep(100)
        }
        automation.takeScreenshot()?.let { bitmap ->
            File(context.cacheDir, "document-qa-ui-failure.png").outputStream().use {
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
            bitmap.recycle()
        }
        error("System document save UI did not appear; window packages=$packages")
    }

    private fun findSave(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEnabled && node.isClickable &&
            (node.viewIdResourceName?.endsWith(":id/button1") == true ||
             node.viewIdResourceName?.endsWith(":id/container_save") == true ||
             node.text?.toString()?.lowercase() in listOf("save", "保存"))) return node
        for (index in 0 until node.childCount) {
            node.getChild(index)?.let { findSave(it)?.let { result -> return result } }
        }
        return null
    }

    private class Result : MethodChannel.Result {
        val finished = CountDownLatch(1)
        var value: Any? = null
        var code = ""
        var message = ""
        override fun success(result: Any?) { value = result; finished.countDown() }
        override fun error(errorCode: String, errorMessage: String?, details: Any?) {
            code = errorCode; message = errorMessage.orEmpty(); finished.countDown()
        }
        override fun notImplemented() { code = "not_implemented"; finished.countDown() }
        fun await() { assertTrue("Document result did not complete", finished.await(30, TimeUnit.SECONDS)) }
    }

    companion object {
        private const val PICKER_TIMEOUT_MS = 30_000L
    }
}
