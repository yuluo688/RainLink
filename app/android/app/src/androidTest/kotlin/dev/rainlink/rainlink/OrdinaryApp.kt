package dev.rainlink.rainlink

import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage

/** Native fixtures must not race the ordinary Flutter startup preference sync. */
internal fun waitForOrdinaryAppReady(activity: MainActivity? = null) {
    val instrumentation = InstrumentationRegistry.getInstrumentation()
    val deadline = SystemClock.uptimeMillis() + 30_000
    while (SystemClock.uptimeMillis() < deadline) {
        var ready = false
        instrumentation.runOnMainSync {
            val current = activity ?: ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(Stage.RESUMED).filterIsInstance<MainActivity>().singleOrNull()
            ready = current?.mobileIntegration?.notificationsConfigured == true
        }
        if (ready) return
        Thread.sleep(50)
    }
    error("Ordinary Flutter initialization did not acknowledge notification preferences")
}
