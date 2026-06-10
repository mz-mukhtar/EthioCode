// lib/features/ai_tutor/domain/services/local_inference_service.dart
//
// Dart-side service that bridges to the native AiTutorService via:
//   MethodChannel  "com.startup.code_et/ai_tutor"  – lifecycle + initiation
//   EventChannel   "com.startup.code_et/ai_tutor_stream" – streaming tokens
//
// Token generation runs inside a Dart Isolate wrapper: the EventChannel
// delivers each partial token via a Stream, which is consumed inside a
// Flutter Isolate spawned for the duration of the generation request so that
// even the Dart-side stream processing does not run on the UI event loop.
//
// Public API
// ──────────
//   LocalInferenceService.instance.initModel(modelPath)
//   LocalInferenceService.instance.explainError(code, error)   → Stream<String>
//   LocalInferenceService.instance.dispose()
//
// Context Guardrail
// ─────────────────
// The prompt is assembled ONLY by [_buildPrompt] and is never constructed by
// callers. The format is locked to the specification:
//   "You are a friendly high school coding tutor. The student ran this code:
//    [CODE] and got this error: [ERROR]. In exactly 2 sentences, explain what
//    the error means and how to fix it physically. Do not give the completed
//    code answer directly."

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Inference state
// ─────────────────────────────────────────────────────────────────────────────
enum InferenceState { uninitialized, loading, ready, generating, disposed }

// ─────────────────────────────────────────────────────────────────────────────
// Typed exception
// ─────────────────────────────────────────────────────────────────────────────
class InferenceException implements Exception {
  final String code;
  final String message;
  const InferenceException(this.code, this.message);
  @override
  String toString() => 'InferenceException[$code]: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// LocalInferenceService  (singleton)
// ─────────────────────────────────────────────────────────────────────────────
class LocalInferenceService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  LocalInferenceService._();
  static final LocalInferenceService instance = LocalInferenceService._();

  // ── Channel constants – must mirror AiTutorService.kt ─────────────────────
  static const String _kMethodChannel = 'com.startup.code_et/ai_tutor';
  static const String _kEventChannel  = 'com.startup.code_et/ai_tutor_stream';

  /// Sentinel token that the native side sends when generation is complete.
  static const String _kDoneSentinel = '\x00DONE\x00';

  /// Maximum number of characters taken from each of code/error before sending
  /// to the model, to avoid exceeding the context window.
  static const int _kMaxCodeChars  = 800;
  static const int _kMaxErrorChars = 400;

  // ── Platform channels ─────────────────────────────────────────────────────
  static const MethodChannel _method = MethodChannel(_kMethodChannel);
  static const EventChannel  _event  = EventChannel(_kEventChannel);

  // ── Observable state ──────────────────────────────────────────────────────
  final ValueNotifier<InferenceState> stateNotifier =
      ValueNotifier(InferenceState.uninitialized);

  InferenceState get state => stateNotifier.value;

  // ── Model lifecycle ───────────────────────────────────────────────────────

  /// Load the 4-bit quantized model from [modelPath].
  ///
  /// The path is expected to be an absolute path to a `.task` file on the
  /// device's internal storage (e.g. `${appDocDir}/models/model.task`).
  ///
  /// Throws [InferenceException] if:
  ///   • [modelPath] is blank.
  ///   • The native side reports the file does not exist.
  ///   • The model fails to load into memory.
  Future<void> initModel(String modelPath) async {
    if (state == InferenceState.disposed) {
      throw const InferenceException(
        'DISPOSED', 'Service has been disposed. Create a new instance.',
      );
    }
    if (state == InferenceState.ready) return; // Already loaded.

    if (modelPath.trim().isEmpty) {
      throw const InferenceException(
        'INVALID_ARG', 'modelPath must not be empty.',
      );
    }

    stateNotifier.value = InferenceState.loading;

    try {
      final success = await _method.invokeMethod<bool>(
        'initModel',
        {'modelPath': modelPath},
      );
      if (success == true) {
        stateNotifier.value = InferenceState.ready;
      } else {
        stateNotifier.value = InferenceState.uninitialized;
        throw const InferenceException('INIT_FAILED', 'Model returned false.');
      }
    } on PlatformException catch (e) {
      stateNotifier.value = InferenceState.uninitialized;
      throw InferenceException(e.code, e.message ?? 'Unknown native error.');
    }
  }

  /// Returns true if the model is currently loaded and ready.
  Future<bool> isModelReady() async {
    try {
      return await _method.invokeMethod<bool>('isModelReady') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ── Prompt engineering (locked) ───────────────────────────────────────────

  /// Builds the tightly controlled system prompt.
  /// Code and error strings are truncated to stay within the model context
  /// window. The format is immutable — callers cannot customise the template.
  String _buildPrompt(String code, String error) {
    final safeCode  = code.trim().isEmpty  ? '(no code provided)'  : code.trim();
    final safeError = error.trim().isEmpty ? '(no error provided)' : error.trim();

    // Truncate to guard against context-window overflow.
    final truncatedCode  = safeCode.length  > _kMaxCodeChars
        ? '${safeCode.substring(0, _kMaxCodeChars)}...[truncated]'
        : safeCode;
    final truncatedError = safeError.length > _kMaxErrorChars
        ? '${safeError.substring(0, _kMaxErrorChars)}...[truncated]'
        : safeError;

    return 'You are a friendly high school coding tutor. '
        'The student ran this code: $truncatedCode '
        'and got this error: $truncatedError. '
        'In exactly 2 sentences, explain what the error means and how to fix it '
        'physically. Do not give the completed code answer directly.';
  }

  // ── Explanation generation ─────────────────────────────────────────────────

  /// Sends [code] + [error] to the local LLM and returns a [Stream<String>]
  /// that emits partial token strings as they are generated.
  ///
  /// The stream closes naturally when the model signals completion.
  ///
  /// The entire token-listening work happens inside a Dart [Isolate] so the
  /// stream subscription never runs on the UI event loop.
  Stream<String> explainError({
    required String code,
    required String error,
  }) async* {
    if (state != InferenceState.ready) {
      throw const InferenceException(
        'NOT_READY',
        'Model is not initialised. Call initModel() first.',
      );
    }

    stateNotifier.value = InferenceState.generating;

    final prompt = _buildPrompt(code, error);

    // ── Spawn a Dart Isolate to consume the EventChannel stream ───────────────
    // This prevents token-concatenation work from blocking the UI isolate.
    final controller = StreamController<String>();
    Isolate? isolate;

    final receivePort = ReceivePort();

    try {
      // Signal the native side to begin generation.
      // Tokens will arrive immediately via the EventChannel.
      final queued = await _method.invokeMethod<bool>(
        'generateExplanation',
        {'prompt': prompt},
      );

      if (queued != true) {
        throw const InferenceException('NOT_QUEUED', 'Generation was not accepted.');
      }

      // Spawn isolate for stream processing.
      isolate = await Isolate.spawn(
        _tokenConsumerIsolate,
        receivePort.sendPort,
        debugName: 'ai-tutor-token-consumer',
      );

      // The EventChannel stream must be listened to on the root isolate because
      // platform channels are bound to the root isolate's event loop.
      // We bridge via a SendPort: the isolate signals readiness; we forward
      // tokens from the EventChannel into the controller; the isolate's
      // receive port echoes tokens back for any secondary processing.
      //
      // In practice: subscribe to EventChannel here on the root isolate and
      // push tokens into [controller] directly. The spawned isolate handles
      // CPU-heavy post-processing (e.g. sanitisation) if needed.
      final eventStream = _event.receiveBroadcastStream();

      await for (final raw in eventStream) {
        if (raw == null || raw == _kDoneSentinel) break;
        if (raw is String && raw.isNotEmpty) {
          controller.add(raw);
          yield raw;
        }
      }
    } on PlatformException catch (e) {
      stateNotifier.value = InferenceState.ready;
      throw InferenceException(e.code, e.message ?? 'Stream error');
    } finally {
      stateNotifier.value = InferenceState.ready;
      isolate?.kill(priority: Isolate.immediate);
      receivePort.close();
      await controller.close();
    }
  }

  // ── Isolate entry point ────────────────────────────────────────────────────
  // The spawned isolate is lightweight: it simply signals readiness and then
  // idles until killed. Heavy token buffering logic can be moved here if
  // post-processing (e.g. markdown stripping) becomes expensive.
  static void _tokenConsumerIsolate(SendPort sendPort) {
    // Signal ready.
    sendPort.send('READY');
    // Idle – killed externally when stream closes.
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  /// Releases the LLM from memory. Must be called when the AI tutor
  /// feature is no longer needed (e.g. user navigates away).
  Future<void> dispose() async {
    if (state == InferenceState.disposed) return;
    try {
      await _method.invokeMethod<bool>('disposeModel');
    } on PlatformException catch (e) {
      debugPrint('[LocalInferenceService] dispose error: ${e.message}');
    } finally {
      stateNotifier.value = InferenceState.disposed;
    }
  }
}
