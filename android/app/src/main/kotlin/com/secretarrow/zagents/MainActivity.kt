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
import java.io.File

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
                        "requestIgnoreBatteryOptimization" -> {
                            requestIgnoreBatteryOptimization()
                        }
                        "isIgnoringBatteryOptimizations" -> {
                            result.success(isIgnoringBatteryOptimizations())
                            true
                        }
                        "getSdkInt" -> {
                            result.success(Build.VERSION.SDK_INT)
                            true
                        }
                        "exportChatFolder" -> {
                            // v1.29.0: copy a chat workspace folder into
                            // Download/ZAgents/<name>/ via MediaStore (no
                            // permission needed on API 29+). Replies with
                            // the exported file count (its own result).
                            @Suppress("UNCHECKED_CAST")
                            val files = call.argument<ArrayList<Map<String, String>>>(
                                "files",
                            ) ?: ArrayList()
                            exportChatFolder(
                                name = call.argument<String>("name") ?: "",
                                files = files,
                                result = result,
                            )
                            true
                        }
                        else -> false
                    }
                } catch (_: Exception) {
                    false
                }
                if (call.method != "getPendingSession" &&
                    call.method != "isIgnoringBatteryOptimizations" &&
                    call.method != "getSdkInt" &&
                    call.method != "exportChatFolder"
                ) {
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

    /// Opens the system "ignore battery optimizations" dialog (v1.28.0).
    /// The REQUEST_IGNORE_BATTERY_OPTIMIZATIONS permission is declared in
    /// the manifest; the user still decides — the dialog is dismissible.
    private fun requestIgnoreBatteryOptimization(): Boolean {
        return try {
            val intent = Intent(
                android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                android.net.Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            // Some OEM builds ship without the settings activity.
            false
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return try {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (_: Exception) {
            false
        }
    }

    /// Copies every given file into `Download/ZAgents/<name>/<rel>` via
    /// MediaStore (v1.29.0). Own previous export of the SAME folder is
    /// removed first, so re-exporting replaces it instead of piling up
    /// duplicates. Own-app MediaStore contributions need no permission on
    /// API 29+; below 29 the Dart side falls back to zip + share.
    /// Replies with the exported file count, or -1 when nothing exported.
    private fun exportChatFolder(
        name: String,
        files: List<Map<String, String>>,
        result: MethodChannel.Result,
    ): Boolean {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                result.success(-2) // Dart falls back to zip + share sheet
                return true
            }
            val safeName = name
                .replace(Regex("[^A-Za-z0-9 _().-]"), "_")
                .trim()
                .take(60)
                .ifEmpty { "chat" }
            val baseRel = "Download/ZAgents/$safeName/"
            val resolver = contentResolver
            val downloads = android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI
            // Replace the previous export of this exact folder (own files).
            try {
                resolver.query(
                    downloads,
                    arrayOf(android.provider.MediaStore.MediaColumns._ID),
                    "${android.provider.MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                    arrayOf("$baseRel%"),
                    null,
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(0)
                        try {
                            resolver.delete(
                                android.content.ContentUris.withAppendedId(downloads, id),
                                null,
                                null,
                            )
                        } catch (_: Exception) {
                            // Someone else's entry or already gone — skip.
                        }
                    }
                }
            } catch (_: Exception) {
                // Query/delete cleanup is best-effort.
            }
            var count = 0
            for (file in files) {
                val rel = (file["rel"] ?: "").replace('\\', '/')
                val abs = file["abs"] ?: ""
                if (rel.isEmpty() || abs.isEmpty()) continue
                if (rel.split('/').any { it == ".." }) continue
                val src = File(abs)
                if (!src.isFile) continue
                val dirPart = if (rel.contains('/')) rel.substringBeforeLast('/') + "/" else ""
                val display = rel.substringAfterLast('/')
                if (display.isEmpty()) continue
                val values = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, display)
                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, baseRel + dirPart)
                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mimeFor(display))
                }
                val outUri = resolver.insert(downloads, values) ?: continue
                try {
                    resolver.openOutputStream(outUri)?.use { os ->
                        src.inputStream().use { it.copyTo(os) }
                    } ?: run {
                        resolver.delete(outUri, null, null)
                        continue
                    }
                    count++
                } catch (_: Exception) {
                    try { resolver.delete(outUri, null, null) } catch (_: Exception) {}
                }
            }
            result.success(count)
            return true
        } catch (e: Exception) {
            result.error("EXPORT_FAILED", e.message ?: "export failed", null)
            return false
        }
    }

    private fun mimeFor(name: String): String = when (
        name.substringAfterLast('.', "").lowercase()
    ) {
        "json" -> "application/json"
        "txt" -> "text/plain"
        "md" -> "text/markdown"
        "csv" -> "text/csv"
        "html" -> "text/html"
        "css" -> "text/css"
        "js" -> "text/javascript"
        "xml" -> "application/xml"
        "svg" -> "image/svg+xml"
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "webp" -> "image/webp"
        "gif" -> "image/gif"
        "pdf" -> "application/pdf"
        "zip" -> "application/zip"
        else -> "application/octet-stream"
    }

    companion object {
        private const val CHANNEL_DONE = "zagents_done"
        private const val NOTIF_DONE_ID = 2001
        const val EXTRA_PENDING_SESSION = "pending_session"
    }
}
