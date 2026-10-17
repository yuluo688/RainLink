package dev.rainlink.rainlink.notifications

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** The QA harness revokes runtime permission before starting this process. */
@RunWith(AndroidJUnit4::class)
class AndroidNotificationPermissionTest {
    @Test fun actualSystemNotificationBlockCannotBeReportedAsDelivery() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        assertEquals(PackageManager.PERMISSION_DENIED, context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS))
        AndroidNotifications.initialize(context)
        try {
            AndroidNotifications.configure(true, true)
            assertFalse(AndroidNotifications.status().getValue("allowed"))
            assertFalse(AndroidNotifications.status().getValue("connectionAllowed"))
            assertFalse(AndroidNotifications.status().getValue("expiryAllowed"))
            assertThrows(IllegalStateException::class.java) { AndroidNotifications.expiry(1, 0) }
            AndroidNotifications.connection("不应收到的测试通知")
            waitForNoNotification(AndroidNotifications.CONNECTION_ID)
            waitForNoNotification(AndroidNotifications.EXPIRY_ID)
            assertFalse(manager.activeNotifications.any { it.id == AndroidNotifications.CONNECTION_ID || it.id == AndroidNotifications.EXPIRY_ID })
            assertThrows(IllegalArgumentException::class.java) { AndroidNotifications.expiry(0, 0) }
            assertThrows(IllegalArgumentException::class.java) { AndroidNotifications.expiry(-1, 1) }
        } finally {
            AndroidNotifications.configure(false, false)
        }
    }
}
