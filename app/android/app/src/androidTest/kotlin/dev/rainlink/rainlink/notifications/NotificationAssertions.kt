package dev.rainlink.rainlink.notifications

import android.app.Notification
import android.app.NotificationManager
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry

internal fun waitForNotification(id: Int, text: String? = null): Notification {
    val manager = InstrumentationRegistry.getInstrumentation().targetContext.getSystemService(NotificationManager::class.java)
    val deadline = SystemClock.uptimeMillis() + 5_000
    while (SystemClock.uptimeMillis() < deadline) {
        val notification = manager.activeNotifications.firstOrNull { it.id == id }?.notification
        if (notification != null && (text == null || notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString() == text)) return notification
        Thread.sleep(50)
    }
    error("System did not record notification $id with expected text")
}

internal fun waitForNoNotification(id: Int) {
    val manager = InstrumentationRegistry.getInstrumentation().targetContext.getSystemService(NotificationManager::class.java)
    val deadline = SystemClock.uptimeMillis() + 5_000
    while (SystemClock.uptimeMillis() < deadline) {
        if (manager.activeNotifications.none { it.id == id }) return
        Thread.sleep(50)
    }
    error("System did not remove notification $id")
}
