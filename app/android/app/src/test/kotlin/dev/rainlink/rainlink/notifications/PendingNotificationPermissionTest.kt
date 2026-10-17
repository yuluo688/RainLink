package dev.rainlink.rainlink.notifications

import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test

class PendingNotificationPermissionTest {
    @Test fun timeoutReservesTheDialogUntilItsLateCallbackAndDoesNotCompleteARetry() {
        val pending = PendingNotificationPermission()
        val original = Result()
        pending.start("notification-1-1", original)
        pending.cancel("notification-1-1")
        assertEquals(listOf("cancelled"), original.replies)
        assertTrue(pending.dialogOpen)
        val retry = Result()
        assertThrows(IllegalStateException::class.java) { pending.start("notification-1-2", retry) }
        pending.complete(mapOf("allowed" to true))
        assertEquals(listOf("cancelled"), original.replies)
        assertTrue(retry.replies.isEmpty())
        assertFalse(pending.dialogOpen)
        pending.start("notification-1-2", retry)
        pending.complete(mapOf("allowed" to false))
        assertEquals(listOf(mapOf("allowed" to false)), retry.replies)
    }

    @Test fun unrelatedCancellationCannotDismissTheCurrentRequest() {
        val pending = PendingNotificationPermission()
        val result = Result()
        pending.start("notification-2-1", result)
        pending.cancel("notification-other")
        pending.cancel(null)
        assertTrue(result.replies.isEmpty())
        pending.complete(mapOf("allowed" to true))
        assertEquals(listOf(mapOf("allowed" to true)), result.replies)
    }

    @Test fun launchFailureReleasesOnlyItsOwnRequest() {
        val pending = PendingNotificationPermission()
        val result = Result()
        pending.start("notification-3-1", result)
        pending.abortLaunch(Result())
        assertTrue(pending.dialogOpen)
        pending.abortLaunch(result)
        assertFalse(pending.dialogOpen)
        assertTrue(result.replies.isEmpty())
        pending.complete(mapOf("allowed" to true))
        assertTrue(result.replies.isEmpty())
    }

    @Test fun activityDisposalCompletesAtMostOnceAndReleasesItsDialog() {
        val pending = PendingNotificationPermission()
        val result = Result()
        pending.start("notification-4-1", result)
        pending.dispose()
        pending.dispose()
        pending.complete(mapOf("allowed" to true))
        assertEquals(listOf("cancelled"), result.replies)
        assertFalse(pending.dialogOpen)
    }

    @Test fun recreatedActivityDrainsTheOldDialogBeforeAcceptingANewCaller() {
        val pending = PendingNotificationPermission(dialogAlreadyOpen = true)
        val retry = Result()
        assertThrows(IllegalStateException::class.java) { pending.start("notification-5-1", retry) }
        pending.complete(mapOf("allowed" to true))
        assertTrue(retry.replies.isEmpty())
        pending.start("notification-5-1", retry)
        pending.complete(mapOf("allowed" to false))
        assertEquals(listOf(mapOf("allowed" to false)), retry.replies)
    }

    private class Result : MethodChannel.Result {
        val replies = mutableListOf<Any?>()
        override fun success(result: Any?) { replies.add(result) }
        override fun error(code: String, message: String?, details: Any?) { replies.add(code) }
        override fun notImplemented() { error("Unexpected missing method") }
    }
}
