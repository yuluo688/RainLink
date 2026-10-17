package dev.rainlink.rainlink.notifications

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidNotificationsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun expiryContainsOnlyCountsAndItsRealPendingIntentOpensGroups() {
        AndroidNotifications.initialize(context)
        try {
            assertTrue(AndroidNotifications.status()["expiryAllowed"] == true)
            assertEquals(mapOf("connection" to true, "subscriptionExpiry" to true), AndroidNotifications.configure(true, true))
            assertTrue(AndroidNotifications.expiry(2, 1))
            val notification = waitForNotification(AndroidNotifications.EXPIRY_ID)
            val text = notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
            assertEquals("2 个订阅将在 3 天内到期，1 个订阅已到期", text)
            assertEquals(context.packageName, notification.contentIntent.creatorPackage)
            assertTrue(notification.smallIcon != null)
            assertEquals(Notification.VISIBILITY_PRIVATE, notification.visibility)
            notification.contentIntent.send()
            waitForText("订阅自动成组")
        } finally {
            AndroidNotifications.configure(false, false)
            waitForNoNotification(AndroidNotifications.EXPIRY_ID)
        }
    }

    private fun waitForText(text: String) {
        val automation = instrumentation.uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val deadline = SystemClock.uptimeMillis() + 30_000
        while (SystemClock.uptimeMillis() < deadline) {
            val roots = listOfNotNull(automation.rootInActiveWindow) + automation.windows.mapNotNull { it.root }
            if (roots.any { hasText(it, text) }) return
            Thread.sleep(100)
        }
        error("The notification did not open the actual groups page")
    }

    private fun hasText(node: AccessibilityNodeInfo, text: String): Boolean {
        if (node.text?.contains(text) == true || node.contentDescription?.contains(text) == true) return true
        for (index in 0 until node.childCount) {
            if (node.getChild(index)?.let { hasText(it, text) } == true) return true
        }
        return false
    }
}
