package com.example.ethiocode

// ─────────────────────────────────────────────────────────────────────────────
// MainActivity.kt
//
// Responsibilities:
//   1. Initialise Chaquopy's Android platform bridge exactly once.
//   2. Register a MethodChannel "com.startup.code_et/python_engine" that
//      accepts a "runPython" call with a code-string argument.
//   3. Dispatch Python execution onto a dedicated background thread so that
//      long-running or infinite loops (while True:) cannot block the Flutter
//      UI thread.  Responses are posted back onto the Flutter main thread via
//      Handler(mainLooper).
//   4. Return a structured result map { stdout, stderr, error } to Dart.
//
// Threading model:
//   UI Thread ──► MethodChannel.setMethodCallHandler callback (called on UI thread)
//                  └─► pythonExecutor.submit { ... }  (submitted to single-thread pool)
//                          └─► Python.getInstance().runCode(...)
//                                  └─► Handler(mainLooper).post { result.success(...) }
//
// The Chaquopy Python interpreter is NOT thread-safe with respect to GIL
// management; running it on a single dedicated thread avoids GIL contention
// while still keeping the UI thread free.
// ─────────────────────────────────────────────────────────────────────────────

import android.os.Handler
import android.os.Looper
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class MainActivity : FlutterActivity() {

    companion object {
        /** The channel name used on both the Dart and Kotlin sides. */
        private const val PYTHON_CHANNEL = "com.startup.code_et/python_engine"

        /** Hard execution timeout in seconds – mirrored in runner.py. */
        private const val EXEC_TIMEOUT_SEC = 5L

        /** Extra grace period before we forcibly cancel the Future. */
        private const val CANCEL_GRACE_SEC = 2L
    }

    // ── Dedicated single-thread executor for Python calls ───────────────────
    // A single-thread pool ensures Python calls are serialised (no GIL fights)
    // while keeping the Android main thread free.
    private val pythonExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "ethiocode-python-runner").also { it.isDaemon = true }
    }

    // Holds a reference to the currently running Future so we can cancel it
    // if a new run request arrives before the previous one completes.
    private val currentFuture = AtomicReference<Future<*>>(null)

    // ── Main-thread handler used to post results back to Flutter ─────────────
    private val mainHandler = Handler(Looper.getMainLooper())

    // ────────────────────────────────────────────────────────────────────────
    // FlutterEngine configuration
    // ────────────────────────────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Initialise Chaquopy once before any Python call ──────────────────
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        // ── Register MethodChannel ───────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PYTHON_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "runPython" -> handleRunPython(call.arguments, result)
                "cancelExecution" -> handleCancelExecution(result)
                else -> result.notImplemented()
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // runPython handler
    // ────────────────────────────────────────────────────────────────────────
    private fun handleRunPython(arguments: Any?, result: MethodChannel.Result) {
        val code = (arguments as? String)?.takeIf { it.isNotBlank() }
        if (code == null) {
            result.error(
                "INVALID_ARGS",
                "Expected a non-empty String argument for 'runPython'.",
                null,
            )
            return
        }

        // Cancel any in-flight execution so the user gets a fresh result.
        currentFuture.getAndSet(null)?.cancel(true)

        // Submit the Python job onto the background thread.
        val future = pythonExecutor.submit {
            executePythonSafely(code, result)
        }
        currentFuture.set(future)

        // Schedule a watchdog that cancels the future if the Python-level
        // timeout hasn't fired within EXEC_TIMEOUT + CANCEL_GRACE seconds.
        mainHandler.postDelayed(
            { future.cancel(true) },
            TimeUnit.SECONDS.toMillis(EXEC_TIMEOUT_SEC + CANCEL_GRACE_SEC),
        )
    }

    // ────────────────────────────────────────────────────────────────────────
    // Python execution (runs on pythonExecutor thread, NOT the UI thread)
    // ────────────────────────────────────────────────────────────────────────
    private fun executePythonSafely(code: String, result: MethodChannel.Result) {
        try {
            val py = Python.getInstance()

            // runner.py is bundled inside the APK by Chaquopy.
            val runnerModule = py.getModule("runner")

            // Call runner.run_code(source, timeout_seconds).
            val pyResult = runnerModule.callAttr(
                "run_code",
                code,
                EXEC_TIMEOUT_SEC.toInt(),
            )

            // Decode the returned Python dict into Kotlin types.
            val stdout = pyResult["stdout"]?.toString() ?: ""
            val stderr = pyResult["stderr"]?.toString() ?: ""
            val hasError = pyResult["error"]?.toBoolean() ?: false

            val responseMap = mapOf(
                "stdout" to stdout,
                "stderr" to stderr,
                "error"  to hasError,
            )

            // Post success back onto the Flutter main thread.
            mainHandler.post { result.success(responseMap) }

        } catch (e: InterruptedException) {
            // The future was cancelled (e.g. a new run was requested).
            // Do NOT call result.success/error – the channel result is already
            // owned by the canceller.
            Thread.currentThread().interrupt()
        } catch (e: Exception) {
            val errorMsg = buildString {
                append(e.javaClass.simpleName)
                if (!e.message.isNullOrBlank()) {
                    append(": ")
                    append(e.message)
                }
            }
            mainHandler.post {
                result.error("PYTHON_EXCEPTION", errorMsg, null)
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // cancelExecution handler – lets the Dart side abort a long run manually.
    // ────────────────────────────────────────────────────────────────────────
    private fun handleCancelExecution(result: MethodChannel.Result) {
        val cancelled = currentFuture.getAndSet(null)?.cancel(true) ?: false
        result.success(cancelled)
    }

    // ────────────────────────────────────────────────────────────────────────
    // Lifecycle cleanup
    // ────────────────────────────────────────────────────────────────────────
    override fun onDestroy() {
        super.onDestroy()
        pythonExecutor.shutdownNow()
    }
}
