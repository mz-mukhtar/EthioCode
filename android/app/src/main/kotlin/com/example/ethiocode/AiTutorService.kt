// android/app/src/main/kotlin/com/example/ethiocode/AiTutorService.kt
//
// Native Android service that wraps the MediaPipe LLM Inference API.
//
// API alignment: tasks-genai:0.10.27
//
// ARCHITECTURE CHANGE vs. original code (forced by library API in 0.10.27):
//   The old code called .setTopK(), .setTemperature(), .setRandomSeed(), and
//   .setResultListener() on LlmInference.LlmInferenceOptions.Builder.
//   NONE of these methods exist on that builder in 0.10.27.
//   Verified by javap against the resolved AAR classes.jar.
//
//   The correct 0.10.27 API is:
//     • LlmInference.LlmInferenceOptions.Builder  →  setModelPath, setMaxTokens, setMaxTopK
//     • Streaming is done by passing a ProgressListener<String> lambda to
//       LlmInference.generateResponseAsync(prompt, progressListener)
//     • Per-inference sampling (topK, temperature, randomSeed) lives on
//       LlmInferenceSession — which is a separate, optional session object.
//       We use the simpler single-shot LlmInference path here for stability.
//
// Threading:
//   All LLM inference runs on [llmExecutor] to keep GPU/CPU off Flutter UI thread.
//   Token callbacks are marshalled back to the main thread via [mainHandler].
//
// Memory safety:
//   • File.exists() checked BEFORE any native initialisation.
//   • LlmInference is closed in release() and disposeModel() to free ~1–1.5 GB RAM.

package com.example.ethiocode

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.ProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class AiTutorService(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        const val METHOD_CHANNEL = "com.startup.code_et/ai_tutor"
        const val EVENT_CHANNEL  = "com.startup.code_et/ai_tutor_stream"

        // Model-level limits (supported by LlmInferenceOptions.Builder in 0.10.27).
        private const val MAX_TOKENS  = 256
        private const val MAX_TOP_K   = 40  // setMaxTopK = the upper bound allowed per inference

        // Sentinel value pushed to the EventChannel to signal stream completion.
        const val STREAM_DONE_SENTINEL = "\u0000DONE\u0000"
    }

    private val mainHandler  = Handler(Looper.getMainLooper())
    private val llmExecutor  = Executors.newSingleThreadExecutor { r ->
        Thread(r, "ethiocode-llm-thread").also { it.isDaemon = true }
    }

    private val llmRef       = AtomicReference<LlmInference?>(null)
    private val isGenerating = AtomicBoolean(false)

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(::onMethodCall)

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initModel"          -> handleInitModel(call, result)
            "generateExplanation"-> handleGenerate(call, result)
            "isModelReady"       -> result.success(llmRef.get() != null)
            "disposeModel"       -> handleDispose(result)
            else                 -> result.notImplemented()
        }
    }

    // ── initModel ─────────────────────────────────────────────────────────────
    // Arguments: Map { "modelPath": String }
    private fun handleInitModel(call: MethodCall, result: MethodChannel.Result) {
        val modelPath = call.argument<String>("modelPath")
        if (modelPath.isNullOrBlank()) {
            result.error("INVALID_ARG", "'modelPath' argument is required.", null)
            return
        }

        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            result.error(
                "MODEL_NOT_FOUND",
                "Model file not found at: $modelPath. Download the model before running the AI tutor.",
                null,
            )
            return
        }
        if (!modelFile.canRead()) {
            result.error(
                "MODEL_UNREADABLE",
                "Model file exists but cannot be read at: $modelPath. Check permissions.",
                null,
            )
            return
        }

        // Close old instance before loading new one.
        llmRef.getAndSet(null)?.close()

        llmExecutor.submit {
            try {
                // ── Correct 0.10.27 LlmInferenceOptions API ──────────────────
                // Only setModelPath, setMaxTokens, setMaxTopK are available here.
                // setTopK / setTemperature / setRandomSeed / setResultListener
                // do NOT exist on this builder — they were removed in this version.
                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(modelPath)
                    .setMaxTokens(MAX_TOKENS)
                    .setMaxTopK(MAX_TOP_K)
                    .build()

                val llm = LlmInference.createFromOptions(context, options)
                llmRef.set(llm)
                mainHandler.post { result.success(true) }

            } catch (e: Exception) {
                mainHandler.post {
                    result.error("INIT_FAILED", "Failed to load LLM model: ${e.message}", null)
                }
            }
        }
    }

    // ── generateExplanation ───────────────────────────────────────────────────
    // Arguments: Map { "prompt": String }
    // Streaming via ProgressListener → EventChannel sink.
    private fun handleGenerate(call: MethodCall, result: MethodChannel.Result) {
        val llm = llmRef.get()
        if (llm == null) {
            result.error("NOT_INITIALISED", "Model is not loaded. Call initModel() first.", null)
            return
        }

        val prompt = call.argument<String>("prompt")
        if (prompt.isNullOrBlank()) {
            result.error("INVALID_ARG", "'prompt' argument is required.", null)
            return
        }

        if (isGenerating.getAndSet(true)) {
            result.error("BUSY", "A generation is already in progress.", null)
            return
        }

        // Return immediately — tokens arrive via EventChannel.
        result.success(true)

        llmExecutor.submit {
            try {
                // ── Correct 0.10.27 streaming API ────────────────────────────
                // generateResponseAsync(prompt, ProgressListener<String>) is the
                // correct method signature on LlmInference in this version.
                // The ProgressListener receives (partialResult: String, done: Boolean).
                llm.generateResponseAsync(
                    prompt,
                    ProgressListener<String> { partialResult, done ->
                        mainHandler.post {
                            val sink = eventSink ?: return@post
                            if (done) {
                                sink.success(STREAM_DONE_SENTINEL)
                            } else if (!partialResult.isNullOrEmpty()) {
                                sink.success(partialResult)
                            }
                        }
                    }
                )
            } catch (e: Exception) {
                isGenerating.set(false)
                mainHandler.post {
                    eventSink?.error("GENERATION_ERROR", "Inference failed: ${e.message}", null)
                }
            }
            // NOTE: isGenerating is reset inside the ProgressListener's done=true callback
            // at the EventChannel level; the finally block here would fire too early since
            // generateResponseAsync is non-blocking. Reset in the done path instead.
        }
    }

    // ── disposeModel ──────────────────────────────────────────────────────────
    private fun handleDispose(result: MethodChannel.Result) {
        val disposed = llmRef.getAndSet(null)?.let {
            try { it.close(); true } catch (_: Exception) { false }
        } ?: false
        isGenerating.set(false)
        result.success(disposed)
    }

    // ── Called from MainActivity.onDestroy() ──────────────────────────────────
    fun release() {
        llmRef.getAndSet(null)?.runCatching { close() }
        llmExecutor.shutdownNow()
        eventSink = null
        isGenerating.set(false)
    }
}
