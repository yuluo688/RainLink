package dev.rainlink.rainlink.notifications

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class AndroidMobileIntegration(private val activity: Activity, dialogAlreadyOpen: Boolean = false, private val canRequestPermission: () -> Boolean) : EventChannel.StreamHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var pendingAction: String? = null
    private val permission = PendingNotificationPermission(dialogAlreadyOpen)
    private val work = mutableSetOf<MethodChannel.Result>()
    private var disposed = false
    val requestingPermission get() = permission.dialogOpen
    var notificationsConfigured = false
        private set

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("unavailable", "系统设置接口已关闭", null); return }
        val args = call.arguments as? Map<*, *>
        try {
            when (call.method) {
                "inspectNotifications" -> result.success(AndroidNotifications.status())
                "configureNotifications" -> {
                    val connection = args?.get("connection") as? Boolean ?: throw IllegalArgumentException()
                    val expiry = args["subscriptionExpiry"] as? Boolean ?: throw IllegalArgumentException()
                    work.add(result)
                    worker.execute {
                        val saved = try { AndroidNotifications.configure(connection, expiry) } catch (_: Exception) { null }
                        main.post {
                            if (work.remove(result)) {
                                if (saved == null) result.error("write_failed", "系统通知偏好保存失败", null)
                                else {
                                    notificationsConfigured = true
                                    result.success(saved)
                                }
                            }
                        }
                    }
                }
                "requestNotifications" -> {
                    val id = args?.get("requestId") as? String ?: throw IllegalArgumentException()
                    require(Regex("^notification-[0-9]+-[0-9]+$").matches(id))
                    if (requestingPermission || !canRequestPermission()) { result.error("busy", "请先完成当前系统授权", null); return }
                    if (Build.VERSION.SDK_INT < 33 || AndroidNotifications.status()["allowed"] == true) {
                        result.success(AndroidNotifications.status())
                    } else {
                        permission.start(id, result)
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
                    }
                }
                "cancelNotificationPermission" -> {
                    permission.cancel(args?.get("requestId") as? String)
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
                    result.success(true)
                }
                "notifySubscriptionExpiry" -> {
                    val soon = args?.get("expiringSoon") as? Int ?: throw IllegalArgumentException()
                    val expired = args["expired"] as? Int ?: throw IllegalArgumentException()
                    result.success(AndroidNotifications.expiry(soon, expired))
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            work.remove(result)
            permission.abortLaunch(result)
            result.error("system_failed", "系统通知操作未完成，请检查通知设置后重试", null)
        }
    }

    fun onPermissionResult(request: Int): Boolean {
        if (request != REQUEST_NOTIFICATIONS) return false
        permission.complete(AndroidNotifications.status())
        return true
    }

    fun handleIntent(intent: Intent?) {
        val action = intent?.getStringExtra(AndroidNotifications.ACTION_EXTRA) ?: return
        intent.removeExtra(AndroidNotifications.ACTION_EXTRA)
        if (action !in listOf("overview", "groups")) return
        if (sink == null) pendingAction = action else sink?.success(action)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        pendingAction?.let { events.success(it) }
        pendingAction = null
    }
    override fun onCancel(arguments: Any?) { sink = null }

    fun dispose() {
        disposed = true
        permission.dispose()
        work.forEach { it.error("cancelled", "页面已关闭，系统设置操作已取消", null) }
        work.clear()
        sink?.endOfStream()
        sink = null
        worker.shutdownNow()
    }

    companion object { private const val REQUEST_NOTIFICATIONS = 1003 }
}
