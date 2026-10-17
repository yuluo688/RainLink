package dev.rainlink.rainlink.notifications

import android.Manifest
import android.app.Notification
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import dev.rainlink.rainlink.MainActivity
import dev.rainlink.rainlink.R

/** Optional alerts are independent from the mandatory foreground-service notice. */
internal object AndroidNotifications {
    private lateinit var application: Application
    private val manager get() = application.getSystemService(NotificationManager::class.java)
    private val preferences get() = application.getSharedPreferences("rainlink_notifications", Context.MODE_PRIVATE)

    fun initialize(context: Context) {
        application = requireNotNull(context.applicationContext as? Application)
        manager.createNotificationChannels(listOf(
            NotificationChannel(CONNECTION_CHANNEL, "连接状态提醒", NotificationManager.IMPORTANCE_DEFAULT),
            NotificationChannel(EXPIRY_CHANNEL, "订阅到期提醒", NotificationManager.IMPORTANCE_DEFAULT),
        ))
    }

    fun status(): Map<String, Boolean> {
        val allowed = (Build.VERSION.SDK_INT < 33 || application.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            manager.areNotificationsEnabled()
        fun channelAllowed(id: String) = allowed && manager.getNotificationChannel(id)?.let { it.importance != NotificationManager.IMPORTANCE_NONE } == true
        return mapOf("allowed" to allowed, "connectionAllowed" to channelAllowed(CONNECTION_CHANNEL),
            "expiryAllowed" to channelAllowed(EXPIRY_CHANNEL))
    }

    /** Called on a worker, and acknowledges only a persisted, read-back value. */
    fun configure(connection: Boolean, subscriptionExpiry: Boolean): Map<String, Boolean> {
        check(preferences.edit().putBoolean("connection", connection).putBoolean("subscriptionExpiry", subscriptionExpiry).commit())
        check(preferences.getBoolean("connection", false) == connection &&
            preferences.getBoolean("subscriptionExpiry", false) == subscriptionExpiry)
        if (!connection) manager.cancel(CONNECTION_ID)
        if (!subscriptionExpiry) manager.cancel(EXPIRY_ID)
        return mapOf("connection" to connection, "subscriptionExpiry" to subscriptionExpiry)
    }

    fun connection(text: String) {
        try {
            if (!preferences.getBoolean("connection", false) || status()["connectionAllowed"] != true) return
            manager.notify(CONNECTION_ID, notification(CONNECTION_CHANNEL, text, "overview"))
        } catch (_: RuntimeException) {
            // Alert delivery must never convert an established tunnel into a
            // failed connection. A safe diagnostic remains visible in logcat.
            Log.w("RainLinkNotifications", "System did not accept the connection status notification")
        }
    }

    fun expiry(soon: Int, expired: Int): Boolean {
        require(soon >= 0 && expired >= 0 && soon.toLong() + expired > 0)
        check(preferences.getBoolean("subscriptionExpiry", false) && status()["expiryAllowed"] == true)
        val text = buildList {
            if (soon > 0) add("$soon 个订阅将在 3 天内到期")
            if (expired > 0) add("$expired 个订阅已到期")
        }.joinToString("，")
        manager.notify(EXPIRY_ID, notification(EXPIRY_CHANNEL, text, "groups"))
        return true
    }

    private fun notification(channel: String, text: String, action: String): Notification {
        val intent = Intent(application, MainActivity::class.java)
            .setAction("dev.rainlink.NOTIFICATION.$action")
            .putExtra(ACTION_EXTRA, action)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val open = PendingIntent.getActivity(application, if (action == "groups") EXPIRY_ID else CONNECTION_ID,
            intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(application, channel).setSmallIcon(R.drawable.ic_connection)
            .setContentTitle("RainLink").setContentText(text).setContentIntent(open)
            .setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(if (action == "groups") Notification.CATEGORY_REMINDER else Notification.CATEGORY_STATUS).build()
    }

    internal const val ACTION_EXTRA = "rainlinkNotificationAction"
    internal const val CONNECTION_CHANNEL = "rainlink_connection_events"
    internal const val EXPIRY_CHANNEL = "rainlink_subscription_expiry"
    internal const val CONNECTION_ID = 1043
    internal const val EXPIRY_ID = 1044
}
