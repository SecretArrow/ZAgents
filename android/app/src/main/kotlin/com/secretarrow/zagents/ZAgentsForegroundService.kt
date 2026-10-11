package com.secretarrow.zagents

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

/**
 * Foreground service that keeps the Flutter process (and therefore the
 * Dart agent loop + headless WebView automation) alive while the user is
 * away from the app.
 *
 * Without this, Android treats the app as a cached process once it leaves
 * the screen and may freeze or kill it within minutes — aborting a running
 * agent task mid-flight. With it, the task keeps running in the background
 * and the user sees a persistent status notification they can trust.
 *
 * Contract (driven from Dart over the "zagents/background" MethodChannel):
 *  - ACTION_START  : create the channel, go foreground, acquire a partial
 *                    wake lock so the CPU keeps working with the screen off.
 *  - ACTION_UPDATE : replace the notification text (current agent step).
 *  - ACTION_STOP   : release everything and stop the service.
 */
class ZAgentsForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.secretarrow.zagents.action.START"
        const val ACTION_UPDATE = "com.secretarrow.zagents.action.UPDATE"
        const val ACTION_STOP = "com.secretarrow.zagents.action.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        const val CHANNEL_ID = "zagents_agent"
        const val NOTIFICATION_ID = 20251012
        private const val WAKELOCK_TAG = "ZAgents::agentLoop"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundService()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
                if (text.isNotEmpty()) {
                    notification(text).let {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            startForeground(
                                NOTIFICATION_ID,
                                it,
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                            )
                        } else {
                            startForeground(NOTIFICATION_ID, it)
                        }
                    }
                }
            }
            else -> {
                // ACTION_START (also the default when the intent is null).
                val title = intent?.getStringExtra(EXTRA_TITLE)
                    ?: getString(R.string.app_name)
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
                val notif = notification(title, text)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notif,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notif)
                }
                acquireWakeLock()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun notification(title: String, text: String = ""): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.app_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { setShowBadge(false) },
            )
        }

        // Tapping the notification brings the app back to the foreground.
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
            setReferenceCounted(false)
            // Safety valve: if Dart ever fails to stop the service (crash,
            // process kill), the CPU is not held forever. Real agent runs
            // finish in minutes; 2 hours is a generous upper bound.
            acquire(2 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun stopForegroundService() {
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }
}
