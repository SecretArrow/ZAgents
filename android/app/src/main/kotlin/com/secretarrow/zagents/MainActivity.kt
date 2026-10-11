package com.secretarrow.zagents

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Dart agent loop to [ZAgentsForegroundService] so a running
 * agent task survives backgrounding (foreground service + wake lock +
 * progress notification).
 *
 * Every method is defensive: failures resolve to `false` instead of
 * throwing, so a missing service or OEM-specific restriction can never
 * crash the app.
 */
class MainActivity : FlutterActivity() {

    private fun channelName(): String = "zagents/background"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        else -> false
                    }
                } catch (_: Exception) {
                    false
                }
                result.success(ok)
            }
    }

    private fun serviceIntent(action: String, title: String?, text: String?): Intent =
        Intent(this, ZAgentsForegroundService::class.java).apply {
            this.action = action
            putExtra(ZAgentsForegroundService.EXTRA_TITLE, title)
            putExtra(ZAgentsForegroundService.EXTRA_TEXT, text)
        }
}
