package dev.rainlink.rainlink

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import dev.rainlink.rainlink.core.AndroidCore
import dev.rainlink.rainlink.core.CoreReply
import dev.rainlink.rainlink.export.AndroidDocumentExporter
import dev.rainlink.rainlink.updates.AndroidUpdateInstaller
import dev.rainlink.rainlink.notifications.AndroidMobileIntegration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionRequest: Pair<String, MethodChannel.Result>? = null
    private var permissionDialog: Int? = null
    private var restoredNotificationDialog = false
    private var notificationAsked = false
    internal var documentExporter: AndroidDocumentExporter? = null
        private set
    private var documentChannel: MethodChannel? = null
    internal var updateInstaller: AndroidUpdateInstaller? = null
        private set
    private var updateChannel: MethodChannel? = null
    internal var mobileIntegration: AndroidMobileIntegration? = null
        private set
    private var mobileChannel: MethodChannel? = null
    private var mobileActions: EventChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        permissionDialog = savedInstanceState?.getInt(CORE_PERMISSION_STATE)?.takeIf {
            it == REQUEST_TUNNEL || it == REQUEST_NOTIFICATION
        }
        restoredNotificationDialog = savedInstanceState?.getBoolean(MOBILE_PERMISSION_STATE) == true
        super.onCreate(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        permissionDialog?.let { outState.putInt(CORE_PERMISSION_STATE, it) }
        outState.putBoolean(MOBILE_PERMISSION_STATE, mobileIntegration?.requestingPermission == true)
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AndroidCore.initialize(applicationContext)
        val mobile = AndroidMobileIntegration(this, restoredNotificationDialog) {
            permissionRequest == null && permissionDialog == null
        }
        mobileIntegration = mobile
        mobile.handleIntent(intent)
        mobileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rainlink/mobile").apply {
            setMethodCallHandler(mobile::handle)
        }
        mobileActions = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "rainlink/mobile/actions").apply {
            setStreamHandler(mobile)
        }
        documentExporter = AndroidDocumentExporter(this)
        updateInstaller = AndroidUpdateInstaller(this)
        updateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rainlink/updates").apply {
            setMethodCallHandler { call, result -> updateInstaller?.handle(call, result)
                ?: result.error("unavailable", "安装服务已关闭", null) }
        }
        documentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rainlink/documents").apply {
            setMethodCallHandler { call, result -> documentExporter?.handle(call, result)
                ?: result.error("unavailable", "文件保存服务已关闭", null) }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rainlink/core").apply {
            setMethodCallHandler { call, result ->
                val raw = call.arguments as? String
                if (raw == null || raw.length > 4 * 1024 * 1024) {
                    result.error("invalid_request", "原生请求格式无效", null)
                } else if (call.method == "connect") {
                    if (permissionRequest != null || permissionDialog != null || mobileIntegration?.requestingPermission == true) result.error("busy", "正在等待系统授权", null)
                    else {
                        permissionRequest = raw to result
                        if (Build.VERSION.SDK_INT >= 33 && !notificationAsked &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            notificationAsked = true
                            permissionDialog = REQUEST_NOTIFICATION
                            try {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION)
                            } catch (_: Exception) {
                                failPermissionLaunch()
                            }
                        } else requestTunnelPermission()
                    }
                } else {
                    if (call.method == "cancel" || call.method == "disconnect") cancelPermission()
                    AndroidCore.request(call.method, raw) { reply -> complete(result, reply) }
                }
            }
        }
    }

    private fun requestTunnelPermission() {
        if (permissionRequest == null) return
        try {
            val intent = VpnService.prepare(this)
            if (intent == null) connectAuthorized() else {
                permissionDialog = REQUEST_TUNNEL
                startActivityForResult(intent, REQUEST_TUNNEL)
            }
        } catch (_: Exception) {
            failPermissionLaunch()
        }
    }

    private fun failPermissionLaunch() {
        permissionDialog = null
        val waiting = permissionRequest
        permissionRequest = null
        waiting?.second?.error("permission_unavailable", "系统授权未能打开，请重新尝试", null)
    }

    private fun connectAuthorized() {
        val request = permissionRequest ?: return
        permissionRequest = null
        AndroidCore.connect(request.first) { complete(request.second, it) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (documentExporter?.onActivityResult(requestCode, resultCode, data) == true) return
        if (updateInstaller?.onActivityResult(requestCode, resultCode, data) == true) return
        if (requestCode == REQUEST_TUNNEL) {
            if (permissionDialog != requestCode) return
            permissionDialog = null
            if (resultCode == Activity.RESULT_OK) connectAuthorized()
            else {
                permissionRequest?.second?.error("permission_denied", "未获得系统网络授权", null)
                permissionRequest = null
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (mobileIntegration?.onPermissionResult(requestCode) == true) return
        // Foreground network services may still run when notifications are
        // denied; system tunnel permission remains separately required.
        if (requestCode == REQUEST_NOTIFICATION && permissionDialog == requestCode) {
            permissionDialog = null
            requestTunnelPermission()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        mobileIntegration?.handleIntent(intent)
    }

    private fun complete(result: MethodChannel.Result, reply: CoreReply) {
        if (reply.code.isEmpty()) result.success(reply.value)
        else result.error(reply.code, reply.message, null)
    }

    private fun cancelPermission() {
        permissionRequest?.second?.error("cancelled", "连接已取消", null)
        permissionRequest = null
        // A cancelled caller cannot dismiss the system dialog. Its actual
        // callback must drain before any new connection or notification grant.
    }

    override fun onDestroy() {
        mobileIntegration?.dispose()
        mobileIntegration = null
        mobileChannel?.setMethodCallHandler(null)
        mobileChannel = null
        mobileActions?.setStreamHandler(null)
        mobileActions = null
        documentExporter?.dispose()
        updateInstaller?.dispose()
        updateInstaller = null
        updateChannel?.setMethodCallHandler(null)
        updateChannel = null
        documentExporter = null
        documentChannel?.setMethodCallHandler(null)
        documentChannel = null
        cancelPermission()
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_TUNNEL = 1001
        private const val REQUEST_NOTIFICATION = 1002
        private const val CORE_PERMISSION_STATE = "rainlink.corePermissionDialog"
        private const val MOBILE_PERMISSION_STATE = "rainlink.mobilePermissionDialog"
    }
}
