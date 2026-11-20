package xyz.luaan.antigravitymobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "xyz.luaan.antigravitymobile/android_runtime"
        private const val ALERTS_CHANNEL_ID = "agy_alerts"
        private const val REQ_POST_NOTIFICATIONS = 4201
        private const val REQ_CAMERA = 4202
    }

    private var pendingPermResult: MethodChannel.Result? = null
    private var pendingCameraPermResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "requestNotificationPermission" -> handleRequestNotificationPermission(result)
                    "requestCameraPermission" -> handleRequestCameraPermission(result)
                    "startForegroundService" -> handleStartForegroundService(call, result)
                    "stopForegroundService" -> handleStopForegroundService(result)
                    "setKeepScreenOn" -> handleSetKeepScreenOn(call, result)
                    "showAlertNotification" -> handleShowAlertNotification(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleRequestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingPermResult?.success(false)
        pendingPermResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_POST_NOTIFICATIONS)
    }

    private fun handleRequestCameraPermission(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingCameraPermResult?.success(false)
        pendingCameraPermResult = result
        requestPermissions(arrayOf(Manifest.permission.CAMERA), REQ_CAMERA)
    }

    private fun handleStartForegroundService(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title") ?: "Antigravity Connected"
        val body = call.argument<String>("body") ?: "Maintaining encrypted libp2p session"
        val holdWakeLock = call.argument<Boolean>("holdWakeLock") ?: false
        val intent = Intent(this, AgyForegroundService::class.java).apply {
            putExtra(AgyForegroundService.EXTRA_TITLE, title)
            putExtra(AgyForegroundService.EXTRA_BODY, body)
            putExtra(AgyForegroundService.EXTRA_HOLD_WAKELOCK, holdWakeLock)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
        }
        result.success(true)
    }

    private fun handleStopForegroundService(result: MethodChannel.Result) {
        try {
            stopService(Intent(this, AgyForegroundService::class.java))
        } catch (_: Exception) {
        }
        result.success(true)
    }

    private fun handleSetKeepScreenOn(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
        result.success(true)
    }

    private fun handleShowAlertNotification(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(false)
            return
        }

        val id = call.argument<Int>("id") ?: 2001
        val title = call.argument<String>("title") ?: "Antigravity Alert"
        val body = call.argument<String>("body") ?: ""
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (nm == null) {
            result.success(false)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel(ALERTS_CHANNEL_ID) == null
        ) {
            val ch = NotificationChannel(
                ALERTS_CHANNEL_ID,
                "Antigravity Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Permission approval requests and agent completion alerts"
            }
            nm.createNotificationChannel(ch)
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getActivity(this, id, launchIntent, piFlags)
        val iconRes = applicationInfo.icon.takeIf { it != 0 }
            ?: android.R.drawable.stat_notify_chat

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, ALERTS_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notif = builder
            .setAutoCancel(true)
            .setSmallIcon(iconRes)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(pendingIntent)
            .build()

        try {
            nm.notify(id, notif)
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermResult?.success(granted)
            pendingPermResult = null
        } else if (requestCode == REQ_CAMERA) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingCameraPermResult?.success(granted)
            pendingCameraPermResult = null
        }
    }
}
