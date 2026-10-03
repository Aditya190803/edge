package wtf.openstrap.openstrap_edge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Retains the single Flutter/BLE coordinator when the Activity is closed. */
class EdgeTrackingService : Service() {
    companion object {
        private const val CHANNEL_ID = "edge_tracking"
        private const val NOTIF_ID = 4100
        @Volatile @JvmStatic var running = false
            private set
        @JvmStatic fun start(context: Context) {
            if (!KeepAliveWorker.hasPairedDevice(context)) return
            ContextCompat.startForegroundService(context, Intent(context, EdgeTrackingService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(CHANNEL_ID, "WHOOP 4 sync", NotificationManager.IMPORTANCE_LOW)
        channel.description = "Keeps your WHOOP 4 syncing to Health Connect"
        channel.setShowBadge(false)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!KeepAliveWorker.hasPairedDevice(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val notification = notification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (error: Exception) {
            Log.w("Whoop4Bridge", "Foreground service unavailable", error)
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        // Meet Android's foreground-service deadline before warming Dart.
        EdgeApplication.ensureEngine(this)
        KeepAliveWorker.schedule(this)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("WHOOP 4 Bridge")
            .setContentText("Syncing your band in the background")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(open)
            .setOngoing(true).setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW).build()
    }
}
