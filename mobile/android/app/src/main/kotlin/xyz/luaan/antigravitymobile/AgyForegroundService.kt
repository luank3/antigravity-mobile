package xyz.luaan.antigravitymobile

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
import android.os.PowerManager

class AgyForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "agy_service"
        const val NOTIF_ID = 1001
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_HOLD_WAKELOCK = "holdWakeLock"
        private const val WAKELOCK_TIMEOUT_MS = 15L * 60L * 1000L
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
            ?: "Antigravity Connected"
        val body = intent?.getStringExtra(EXTRA_BODY)?.takeIf { it.isNotBlank() }
            ?: "Maintaining encrypted libp2p session"
        val holdWakeLock = intent?.getBooleanExtra(EXTRA_HOLD_WAKELOCK, false) ?: false

        ensureChannel()
        val notification = buildNotification(title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, notification)
        }

        updateWakeLock(holdWakeLock)
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Antigravity Session",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Keeps the encrypted libp2p tunnel alive while an agent runs"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(title: String, body: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, piFlags)
        val iconRes = applicationInfo.icon.takeIf { it != 0 }
            ?: android.R.drawable.stat_notify_sync

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSmallIcon(iconRes)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun updateWakeLock(hold: Boolean) {
        if (hold) {
            if (wakeLock?.isHeld != true) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
                val wl = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "xyz.luaan.antigravitymobile:stream"
                ).apply {
                    setReferenceCounted(false)
                }
                try {
                    wl.acquire(WAKELOCK_TIMEOUT_MS)
                    wakeLock = wl
                } catch (_: Exception) {
                }
            }
        } else {
            releaseWakeLock()
        }
    }

    private fun releaseWakeLock() {
        val wl = wakeLock ?: return
        try {
            if (wl.isHeld) {
                wl.release()
            }
        } catch (_: Exception) {
        }
        wakeLock = null
    }
}
