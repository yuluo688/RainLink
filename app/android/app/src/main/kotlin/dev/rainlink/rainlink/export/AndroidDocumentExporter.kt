package dev.rainlink.rainlink.export

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Owns one cancellable system document request; no broad storage permission. */
internal class AndroidDocumentExporter(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "rainlink-document-export").apply { isDaemon = true }
    }
    private var pending: Export? = null
    private var disposed = false
    private data class Export(val id: String, val source: File, val result: MethodChannel.Result, val requestCode: Int,
                              val cancellation: CancellationSignal = CancellationSignal())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("unavailable", "文件保存服务已关闭", null); return }
        when (call.method) {
            "cancelExport" -> {
                val id = (call.arguments as? Map<*, *>)?.get("requestId") as? String
                val work = pending
                if (work != null && work.id == id) {
                    work.cancellation.cancel()
                    pending = null
                    activity.finishActivity(work.requestCode)
                    work.result.error("cancelled", "文件导出已取消", null)
                }
                result.success(null)
            }
            "saveDocument" -> save(call, result)
            else -> result.notImplemented()
        }
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "请先完成当前文件保存", null); return }
        val arguments = call.arguments as? Map<*, *>
        val id = arguments?.get("requestId") as? String
        val path = arguments?.get("sourcePath") as? String
        val name = arguments?.get("suggestedName") as? String
        val mime = arguments?.get("mimeType") as? String
        val source = try { path?.let { File(it).canonicalFile } } catch (_: Exception) { null }
        val cache = File(activity.cacheDir, "rainlink-exports").canonicalFile
        val expectedMime = when (name?.substringAfterLast('.', "")?.lowercase()) {
            "csv" -> "text/csv"
            "json" -> "application/json"
            "yaml", "yml" -> "application/yaml"
            "txt" -> "text/plain"
            else -> null
        }
        if (id == null || !Regex("^document-[A-Za-z0-9_-]{1,100}$").matches(id) ||
            source == null || source.parentFile?.name != id || source.parentFile?.parentFile != cache ||
            !source.isFile || source.length() > MAX_BYTES || source.name != "content" ||
            name == null || name.isEmpty() || name.length > 180 || name.any { it.code < 32 || it == '/' || it == '\\' } ||
            mime == null || mime != expectedMime) {
            result.error("invalid_request", "导出文件名称、来源或大小无效", null)
            return
        }
        val requestCode = nextRequest.incrementAndGet()
        if (requestCode > MAX_REQUEST_CODE) {
            result.error("unavailable", "文件保存器需重新打开应用后继续使用", null)
            return
        }
        val work = Export(id, source, result, requestCode)
        pending = work
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
                putExtra(Intent.EXTRA_TITLE, name)
            }, work.requestCode)
        } catch (_: Exception) {
            pending = null
            result.error("unavailable", "无法打开系统文件保存器", null)
        }
    }

    fun onActivityResult(request: Int, result: Int, intent: Intent?): Boolean {
        if (request !in FIRST_REQUEST_CODE..MAX_REQUEST_CODE) return false
        val work = pending?.takeIf { it.requestCode == request } ?: return true
        if (result != Activity.RESULT_OK) {
            pending = null
            work.result.success(null)
            return true
        }
        val uri = intent?.data
        if (uri == null || uri.scheme != "content" || uri.authority.isNullOrEmpty()) {
            pending = null
            work.result.error("invalid_response", "系统未返回有效的文件保存位置", null)
            return true
        }
        worker.execute {
            var failure = false
            try {
                write(work, uri)
            } catch (_: Exception) {
                failure = true
            }
            main.post {
                if (pending !== work) return@post
                pending = null
                if (failure) work.result.error("write_failed", "文件保存失败，所选位置可能有未写完整的文件，请检查后重试", null)
                else work.result.success(uri.toString())
            }
        }
        return true
    }

    private fun write(work: Export, uri: Uri) {
        work.cancellation.throwIfCanceled()
        // Open with the provider's cancellation token. Data is copied off the
        // UI thread and success waits for flush/close, including provider errors.
        val descriptor = activity.contentResolver.openFileDescriptor(uri, "wt", work.cancellation)
            ?: error("Document provider did not open the selected document")
        descriptor.use { target ->
            android.os.ParcelFileDescriptor.AutoCloseOutputStream(target).use { output ->
                work.source.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        work.cancellation.throwIfCanceled()
                        val length = input.read(buffer)
                        if (length < 0) break
                        total += length
                        check(total <= MAX_BYTES)
                        output.write(buffer, 0, length)
                    }
                    output.flush()
                    work.cancellation.throwIfCanceled()
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        pending?.let {
            it.cancellation.cancel()
            activity.finishActivity(it.requestCode)
            it.result.error("cancelled", "页面已关闭，文件导出取消", null)
        }
        pending = null
        worker.shutdownNow()
    }

    companion object {
        private const val FIRST_REQUEST_CODE = 20000
        private const val MAX_REQUEST_CODE = 65534
        private val nextRequest = AtomicInteger(FIRST_REQUEST_CODE - 1)
        private const val MAX_BYTES = 64L * 1024 * 1024
    }
}
