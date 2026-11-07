/*
 * LlmServerChannel.kt — Dart ⇄ Kotlin bridge for the Local AI runtime
 * (v1.51.0).
 *
 * Implements the frozen `zagents/llmserver` MethodChannel contract
 * (lib/services/local_ai/README.md §1): runtime availability, device RAM,
 * start/stop of the llama-server foreground service (LlmServerService),
 * latched run state and the log tail.
 *
 * Design notes:
 *  - Kept OUT of MainActivity on purpose (the Local AI surface is sizeable
 *    and self-contained); MainActivity only registers this class next to
 *    its other channels and stays thin.
 *  - This class holds NO runtime state of its own: every query reads the
 *    live LlmServerProcessHolder singleton that the service updates, so
 *    the channel works no matter what the system did to the Service
 *    object (see LlmServerProcessHolder's doc).
 *  - Every method is defensive, exactly like the other channels in this
 *    app: nothing ever throws across the channel — failures resolve to
 *    safe defaults (false / 0 / empty list / nulls).
 */
package com.secretarrow.zagents

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * v1.51.0 — handler for the `zagents/llmserver` MethodChannel (contract
 * §1). Constructed and registered from MainActivity's
 * configureFlutterEngine; keeps only the app context (see [appContext])
 * to start/stop [LlmServerService] and to inspect `nativeLibraryDir`.
 */
class LlmServerChannel(context: Context) {

    /// Application context on purpose: this object is created once per
    /// FlutterEngine and outlives the Activity that registered it —
    /// holding the Activity itself would leak it. The app context is
    /// enough for everything this channel does (start/stop services,
    /// read nativeLibraryDir, query ActivityManager).
    private val appContext: Context = context.applicationContext

    /// Registers the handler on the engine's binary messenger. Each branch
    /// resolves to a safe value and never throws; the outer catch covers a
    /// malformed argument map (wrong Dart-side types) so no reply path can
    /// ever raise an exception into the channel machinery.
    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "runtimeAvailable" -> result.success(runtimeAvailable())
                        "deviceTotalRamBytes" -> result.success(deviceTotalRamBytes())
                        "startServer" -> result.success(startServer(call))
                        "stopServer" -> result.success(stopServer())
                        "isRunning" -> result.success(LlmServerProcessHolder.snapshotState())
                        "getLogs" -> result.success(LlmServerProcessHolder.snapshotLogs())
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    // Only reachable with malformed arguments (e.g. a
                    // String where an int is expected): resolve to the
                    // safe default instead of throwing across the channel.
                    result.success(false)
                }
            }
    }

    /// `runtimeAvailable` → bool: the llama-server runtime exists in the
    /// app's `nativeLibraryDir` (Android extracted it from the APK's
    /// jniLibs). False on armeabi-v7a builds and on any failure — the
    /// Dart side degrades gracefully and shows the "runtime unavailable"
    /// banner instead of offering a broken Start button.
    private fun runtimeAvailable(): Boolean = try {
        File(appContext.applicationInfo.nativeLibraryDir, LlmServerService.RUNTIME_FILE).isFile
    } catch (_: Exception) {
        false
    }

    /// `deviceTotalRamBytes` → long: `ActivityManager.MemoryInfo.totalMem`
    /// so the UI can warn before downloading models that cannot fit.
    /// 0 = unknown.
    private fun deviceTotalRamBytes(): Long = try {
        val manager = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        info.totalMem
    } catch (_: Exception) {
        0L
    }

    /// `startServer` → bool. False when the runtime file is missing or a
    /// process is already alive (contract §1); true only means "start
    /// command accepted" — the spawn itself happens in the service, and
    /// the Dart side follows up by polling `isRunning` and the /health
    /// endpoint. startForegroundService exists since API 26; the call
    /// always comes from a foreground UI action (the Start button), so
    /// below API 26 a plain start is legal — same reasoning as the
    /// zagents/background "start" case.
    private fun startServer(call: MethodCall): Boolean = try {
        if (!runtimeAvailable() || LlmServerProcessHolder.isRunning()) {
            false
        } else {
            val intent = Intent(appContext, LlmServerService::class.java).apply {
                action = LlmServerService.ACTION_START
                putExtra(LlmServerService.EXTRA_MODEL_PATH, call.argument<String>("modelPath") ?: "")
                putExtra(LlmServerService.EXTRA_ALIAS, call.argument<String>("alias") ?: "")
                putExtra(LlmServerService.EXTRA_PORT, call.argument<Number>("port")?.toInt() ?: 0)
                putExtra(
                    LlmServerService.EXTRA_CONTEXT_SIZE,
                    call.argument<Number>("contextSize")?.toInt() ?: 0,
                )
                putExtra(LlmServerService.EXTRA_THREADS, call.argument<Number>("threads")?.toInt() ?: 0)
                putStringArrayListExtra(
                    LlmServerService.EXTRA_EXTRA_ARGS,
                    ArrayList(call.argument<List<String>>("extraArgs") ?: emptyList()),
                )
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
            true
        }
    } catch (_: Exception) {
        // OEM background-start restrictions, service start failures, … —
        // report "not started"; the Dart side surfaces a failed status.
        false
    }

    /// `stopServer` → bool: always true — idempotent, even when nothing
    /// is running (contract §1). Sends ACTION_STOP to the service via
    /// plain startService (NOT startForegroundService: the stop path
    /// never calls startForeground, which startForegroundService would
    /// demand within 5 s). Intents to the same service are delivered in
    /// order, so a Start immediately followed by a Stop can never leave a
    /// fresh process behind. Belt-and-braces, the child process is also
    /// destroyed directly through the holder — an undeliverable intent
    /// (service already gone, OEM restriction) must never orphan a
    /// llama-server process.
    private fun stopServer(): Boolean {
        try {
            val intent = Intent(appContext, LlmServerService::class.java).apply {
                action = LlmServerService.ACTION_STOP
            }
            appContext.startService(intent)
        } catch (_: Exception) {
            // Nothing running / background restriction — the direct holder
            // kill below already covers the process itself.
        }
        LlmServerProcessHolder.stopProcess()
        return true
    }

    companion object {
        /// Frozen channel name (contract §1) — must match the Dart side's
        /// `MethodChannel('zagents/llmserver')`.
        const val CHANNEL_NAME = "zagents/llmserver"
    }
}
