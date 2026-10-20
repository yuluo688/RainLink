package dev.rainlink.rainlink.updates

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Validates private APK copies before granting the system installer read access. */
internal class AndroidUpdateInstaller(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "rainlink-update-verify").apply { isDaemon = true }
    }
    private val preferences = activity.getSharedPreferences("rainlink-update", Activity.MODE_PRIVATE)
    private val staging = File(activity.cacheDir, "updates/install")
    private var preparing: Work? = null
    private var prepared: Package? = null
    private var installing: Work? = null
    private var disposed = false
    private var waitingFor: Int? = null

    private data class Package(val id: String, val file: File, val bytes: Long, val digest: String,
                               val versionName: String, val versionCode: Long)
    private data class Work(val value: Package, val result: MethodChannel.Result,
                            val cancelled: AtomicBoolean = AtomicBoolean())
    private class InvalidPackage : Exception()
    private class Cancelled : Exception()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("unavailable", "安装服务已关闭", null); return }
        when (call.method) {
            "prepare" -> prepare(call, result)
            "commit" -> commit(call, result)
            "abort", "cancelPrepare" -> abort(call, result)
            "receipt" -> receipt(result)
            else -> result.notImplemented()
        }
    }

    private fun prepare(call: MethodCall, result: MethodChannel.Result) {
        if (preparing != null || prepared != null || installing != null) {
            result.error("busy", "安装操作尚未结束", null); return
        }
        val arguments = call.arguments as? Map<*, *>
        val id = arguments?.get("id") as? String
        val path = arguments?.get("path") as? String
        val bytes = integer(arguments?.get("bytes"))
        val digest = arguments?.get("sha256") as? String
        val versionName = arguments?.get("versionName") as? String
        val versionCode = integer(arguments?.get("versionCode"))
        if (id == null || !ID.matches(id) || path == null || path.length > 4096 ||
            bytes == null || bytes !in 1..MAX_BYTES || digest == null || !HASH.matches(digest) ||
            versionName == null || !VERSION.matches(versionName) || versionCode == null ||
            versionCode !in 1..Int.MAX_VALUE.toLong()) {
            result.error("invalid_package", "安装参数无效", null); return
        }
        val value = Package(id, File(staging, "$id.apk"), bytes, digest, versionName, versionCode)
        val work = Work(value, result)
        preparing = work
        worker.execute {
            var error: String? = null
            try {
                val source = File(path).canonicalFile
                val root = File(activity.cacheDir, "updates").canonicalFile
                if (source.parentFile?.parentFile != root ||
                    !DOWNLOAD.matches(source.parentFile?.name ?: "") ||
                    source.name != "RainLink-$versionName+$versionCode-android-universal.apk" ||
                    !source.isFile || source.length() != bytes) throw InvalidPackage()
                if (!staging.isDirectory && !staging.mkdirs()) throw InvalidPackage()
                if (staging.canonicalFile.parentFile != root) throw InvalidPackage()
                prune()
                source.inputStream().use { input -> FileChannel.open(value.file.toPath(),
                    StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var copied = 0L
                    while (true) {
                        checkCancelled(work)
                        val count = input.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > bytes) throw InvalidPackage()
                        val chunk = ByteBuffer.wrap(buffer, 0, count)
                        while (chunk.hasRemaining()) output.write(chunk)
                    }
                    output.force(true)
                } }
                validate(work)
            } catch (_: Cancelled) { error = "cancelled" }
            catch (_: Exception) { error = "invalid_package" }
            if (error != null && !remove(value)) error = "cleanup_failed"
            val failure = error
            main.post {
                if (preparing !== work) return@post
                preparing = null
                if (work.cancelled.get()) {
                    finishCancelledCopy(work)
                } else if (failure != null) result.error(failure, "安装准备未完成", null)
                else {
                    prepared = value
                    result.success(id)
                }
            }
        }
    }

    private fun checkCancelled(work: Work) {
        if (work.cancelled.get() || Thread.currentThread().isInterrupted) throw Cancelled()
    }

    private fun integer(value: Any?): Long? = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    @Suppress("DEPRECATION") // minSdk 29; retain the compatible PackageManager overload.
    private fun packageInfo(): PackageInfo = activity.packageManager.getPackageInfo(
        activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)

    @Suppress("DEPRECATION")
    private fun validate(work: Work) {
        val value = work.value
        checkCancelled(work)
        if (!value.file.isFile || value.file.canonicalFile.parentFile != staging.canonicalFile ||
            value.file.length() != value.bytes) throw InvalidPackage()
        val digest = MessageDigest.getInstance("SHA-256")
        value.file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                checkCancelled(work)
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val observed = digest.digest().joinToString("") { "%02x".format(it) }
        if (observed != value.digest) throw InvalidPackage()
        val candidate = activity.packageManager.getPackageArchiveInfo(
            value.file.path, PackageManager.GET_SIGNING_CERTIFICATES) ?: throw InvalidPackage()
        val current = packageInfo()
        val signers = candidate.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet()
        val trusted = current.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet()
        if (candidate.packageName != activity.packageName || candidate.versionName != value.versionName ||
            candidate.longVersionCode != value.versionCode || value.versionCode <= current.longVersionCode ||
            signers.isNullOrEmpty() || trusted.isNullOrEmpty() || signers != trusted) throw InvalidPackage()
        checkCancelled(work)
    }

    private fun commit(call: MethodCall, result: MethodChannel.Result) {
        val id = (call.arguments as? Map<*, *>)?.get("id") as? String
        val value = prepared
        if (installing != null || preparing != null) { result.error("busy", "正在安装", null); return }
        if (value == null || value.id != id) { result.error("invalid_package", "安装准备无效", null); return }
        val work = Work(value, result)
        installing = work
        worker.execute {
            var failure: String? = null
            try {
                // Recheck the exact staged bytes immediately before handoff.
                validate(work)
                if (!preferences.edit().putLong("pendingCode", value.versionCode).commit()) throw InvalidPackage()
            } catch (_: Cancelled) { failure = "cancelled" }
            catch (_: Exception) { failure = "invalid_package" }
            val error = failure
            main.post {
                if (installing !== work) return@post
                if (error != null) finish(error)
                else try {
                    if (activity.packageManager.canRequestPackageInstalls()) launchInstaller(work)
                    else {
                        waitingFor = REQUEST_SOURCE
                        activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}")), REQUEST_SOURCE)
                    }
                } catch (_: Exception) { finish("unavailable") }
            }
        }
    }

    @Suppress("DEPRECATION") // System installer remains responsible for explicit consent.
    private fun launchInstaller(work: Work) {
        if (work.cancelled.get()) { finish("cancelled"); return }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", work.value.file)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            clipData = ClipData.newRawUri("RainLink update", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
        }
        waitingFor = REQUEST_INSTALL
        activity.startActivityForResult(intent, REQUEST_INSTALL)
    }

    fun onActivityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request != REQUEST_SOURCE && request != REQUEST_INSTALL) return false
        if (waitingFor != request) return true
        waitingFor = null
        val work = installing ?: return true
        if (request == REQUEST_SOURCE) {
            try {
                if (!activity.packageManager.canRequestPackageInstalls()) finish("permission_denied")
                else launchInstaller(work)
            } catch (_: Exception) { finish("unavailable") }
        } else {
            val installed = try { packageInfo().longVersionCode == work.value.versionCode }
                catch (_: Exception) { false }
            // Opening the installer or an OK-looking activity result alone is
            // never proof that the requested package replaced this app.
            if (result == Activity.RESULT_OK && installed) finish(null)
            else finish(if (result == Activity.RESULT_CANCELED) "cancelled" else "install_failed")
        }
        return true
    }

    private fun finish(code: String?) {
        val work = installing ?: return
        installing = null
        prepared = null
        waitingFor = null
        worker.execute {
            val cleared = preferences.edit().remove("pendingCode").commit()
            val removed = remove(work.value)
            main.post {
                if (!cleared || !removed) work.result.error("cleanup_failed", "安装临时数据清理失败", null)
                else if (code == null) work.result.success(null)
                else work.result.error(code, "系统安装未完成", null)
            }
        }
    }

    private fun abort(call: MethodCall, result: MethodChannel.Result) {
        val id = (call.arguments as? Map<*, *>)?.get("id") as? String
        if (installing?.value?.id == id) { result.error("busy", "请在系统窗口中完成或取消安装", null); return }
        preparing?.takeIf { it.value.id == id }?.cancelled?.set(true)
        val value = prepared?.takeIf { it.id == id }
        if (value == null) { result.success(null); return }
        prepared = null
        worker.execute {
            val removed = remove(value)
            main.post {
                if (removed) result.success(null)
                else result.error("cleanup_failed", "安装临时文件未能清理", null)
            }
        }
    }

    private fun finishCancelledCopy(work: Work) {
        worker.execute {
            val removed = remove(work.value)
            main.post { work.result.error(if (removed) "cancelled" else "cleanup_failed", "安装准备已取消", null) }
        }
    }

    private fun receipt(result: MethodChannel.Result) {
        if (installing != null) { result.error("busy", "正在等待系统安装", null); return }
        worker.execute {
            try {
                val code = preferences.getLong("pendingCode", 0)
                val status = if (code == 0L) null else if (packageInfo().longVersionCode >= code) "installed" else "interrupted"
                if (!preferences.edit().remove("pendingCode").commit()) throw InvalidPackage()
                main.post { result.success(status) }
            } catch (_: Exception) {
                main.post { result.error("unavailable", "无法确认上次安装状态", null) }
            }
        }
    }

    private fun remove(value: Package): Boolean = try {
        value.file.canonicalFile.parentFile == staging.canonicalFile && (!value.file.exists() || value.file.delete())
    } catch (_: Exception) { false }

    private fun prune() {
        val cutoff = System.currentTimeMillis() - 7 * 24 * 60 * 60 * 1000L
        staging.listFiles()?.filter { it.name.matches(Regex("^[a-f0-9]{32}\\.apk$")) && it.lastModified() < cutoff }
            ?.forEach { if (it.canonicalFile.parentFile == staging.canonicalFile && !it.delete()) throw InvalidPackage() }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        preparing?.let {
            it.cancelled.set(true)
            it.result.error("cancelled", "安装准备已结束", null)
            worker.execute { remove(it.value) }
        }
        preparing = null
        // The system may still read a granted URI after Activity destruction.
        // Preserve that one file and the durable receipt until restart/pruning.
        installing?.let { it.cancelled.set(true); it.result.error("cancelled", "系统安装窗口已离开", null) }
        installing = null
        prepared?.takeIf { waitingFor != REQUEST_INSTALL }?.let { value -> worker.execute { remove(value) } }
        prepared = null
        worker.shutdown()
    }

    companion object {
        private const val REQUEST_SOURCE = 2101
        private const val REQUEST_INSTALL = 2102
        private const val MAX_BYTES = 300 * 1024 * 1024L
        private val ID = Regex("^[a-f0-9]{32}$")
        private val HASH = Regex("^[a-f0-9]{64}$")
        private val DOWNLOAD = Regex("^download-[A-Za-z0-9]+$")
        private val VERSION = Regex("^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$")
    }
}
