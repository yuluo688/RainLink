package dev.rainlink.rainlink.notifications

import io.flutter.plugin.common.MethodChannel

/** Keeps ownership of a system dialog even after its Dart caller cancels. */
internal class PendingNotificationPermission(dialogAlreadyOpen: Boolean = false) {
    private var pending: Pair<String, MethodChannel.Result>? = null
    var dialogOpen = dialogAlreadyOpen
        private set

    fun start(id: String, result: MethodChannel.Result) {
        check(!dialogOpen)
        pending = id to result
        dialogOpen = true
    }

    fun cancel(id: String?) {
        if (id != null && pending?.first == id) {
            val result = pending?.second
            pending = null
            // Android cannot dismiss requestPermissions(). Keep the dialog
            // reserved until its actual callback, so it cannot finish a retry.
            result?.error("cancelled", "通知授权已取消", null)
        }
    }

    fun complete(status: Map<String, Boolean>) {
        val result = pending?.second
        pending = null
        dialogOpen = false
        result?.success(status)
    }

    fun abortLaunch(result: MethodChannel.Result) {
        if (pending?.second === result) {
            pending = null
            dialogOpen = false
        }
    }

    fun dispose() {
        val result = pending?.second
        pending = null
        dialogOpen = false
        result?.error("cancelled", "页面已关闭，通知授权已取消", null)
    }
}
