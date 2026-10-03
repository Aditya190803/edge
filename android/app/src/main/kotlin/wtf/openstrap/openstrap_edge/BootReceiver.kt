package wtf.openstrap.openstrap_edge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Boot recovery uses the same cached engine and coordinator as the Activity. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != "android.intent.action.QUICKBOOT_POWERON") return
        if (!KeepAliveWorker.hasPairedDevice(context)) return
        try { EdgeTrackingService.start(context) }
        catch (error: Exception) { Log.w("WHOOP4Bridge", "Boot recovery deferred", error) }
    }
}
