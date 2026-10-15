package com.secretarrow.zagents

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Dart agent loop to [ZAgentsForegroundService] so a running
 * agent task survives backgrounding (foreground service + wake lock +
 * progress notification), and posts local "task finished" notifications
 * (v1.18.0) when a run completes while the app is in the background.
 *
 * Every method is defensive: failures resolve to `false` instead of
 * throwing, so a missing service or OEM-specific restriction can never
 * crash the app.
 *
 * FlutterFragmentActivity (not FlutterActivity) is required by the
 * biometric app-lock (local_auth needs a FragmentActivity host).
 */
class MainActivity : FlutterFragmentActivity() {

    private fun channelName(): String = "zagents/background"

    /// Session id from a tapped done-notification, waiting to be drained
    /// by the Dart side ("getPendingSession").
    private var pendingSessionId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSessionId = intent?.getStringExtra(EXTRA_PENDING_SESSION)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName())
            .setMethodCallHandler { call, result ->
                val ok = try {
                    when (call.method) {
                        "start" -> {
                            // Foreground start: always launched from a user
                            // action in the foreground, so it is allowed on
                            // all Android versions. startForegroundService
                            // exists since API 26; below that a plain start
                            // (while the app is in the foreground) is legal.
                            val intent = serviceIntent(
                                ZAgentsForegroundService.ACTION_START,
                                call.argument<String>("title"),
                                call.argument<String>("text"),
                            )
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            true
                        }
                        "update" -> {
                            // startService() (not startForegroundService()):
                            // only valid while the service is already running,
                            // which is exactly when update() is called.
                            startService(
                                serviceIntent(
                                    ZAgentsForegroundService.ACTION_UPDATE,
                                    null,
                                    call.argument<String>("text"),
                                ),
                            )
                            true
                        }
                        "stop" -> {
                            stopService(
                                Intent(this, ZAgentsForegroundService::class.java),
                            )
                            true
                        }
                        "notifyDone" -> {
                            notifyDone(
                                title = call.argument<String>("title") ?: "ZAgents",
                                text = call.argument<String>("text") ?: "",
                                sessionId = call.argument<String>("sessionId"),
                            )
                        }
                        "getPendingSession" -> {
                            result.success(pendingSessionId)
                            pendingSessionId = null
                            true
                        }
                        else -> false
                    }
                } catch (_: Exception) {
                    false
                }
                if (call.method != "getPendingSession") {
                    result.success(ok)
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_PENDING_SESSION)?.let {
            pendingSessionId = it
        }
    }

    private fun notifyDone(title: String, text: String, sessionId: String?): Boolean {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_DONE,
                "Agent task results",
                NotificationManager.IMPORTANCE_DEFAULT,
            )
            manager.createNotificationChannel(channel)
        }
        val openApp = Intent(this, MainActivity::class.java).apply {
            setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_PENDING_SESSION, sessionId)
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            sessionId?.hashCode() ?: 2001,
            openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder: Notification.Builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_DONE)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        val notification: Notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIF_DONE_ID, notification)
        return true
    }

    private fun serviceIntent(action: String, title: String?, text: String?): Intent =
        Intent(this, ZAgentsForegroundService::class.java).apply {
            this.action = action
            putExtra(ZAgentsForegroundService.EXTRA_TITLE, title)
            putExtra(ZAgentsForegroundService.EXTRA_TEXT, text)
        }

    companion object {
        private const val CHANNEL_DONE = "zagents_done"
        private const val NOTIF_DONE_ID = 2001
        const val EXTRA_PENDING_SESSION = "pending_session"
    }
}
