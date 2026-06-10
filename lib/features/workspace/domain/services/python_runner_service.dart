// lib/features/workspace/domain/services/python_runner_service.dart
//
// Flutter-side wrapper around the "com.startup.code_et/python_engine"
// MethodChannel.
//
// Responsibilities:
//   • Encode the code string into the channel call arguments.
//   • Await the async native response with a Dart-level timeout guard.
//   • Decode the result map into a strongly-typed [ExecutionResult] value object.
//   • Surface errors (channel errors, timeout, invalid args) as structured
//     [ExecutionResult] instances – the caller never needs to catch exceptions.
//   • Expose [cancelExecution()] so the WorkspacePage can abort a long run
//     (e.g. when the user presses a "Stop" button).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Value object returned to the presentation layer.
// ─────────────────────────────────────────────────────────────────────────────

/// Represents the outcome of a single code-execution round-trip.
@immutable
class ExecutionResult {
  /// Everything written to sys.stdout (print() output).
  final String stdout;

  /// Everything written to sys.stderr (tracebacks, timeout notice).
  final String stderr;

  /// True when the execution ended with an exception or was timed out.
  final bool hasError;

  /// Non-null when the channel itself threw (network/platform error).
  final String? channelError;

  const ExecutionResult({
    required this.stdout,
    required this.stderr,
    required this.hasError,
    this.channelError,
  });

  /// Convenience factory for channel-level errors (before any Python ran).
  factory ExecutionResult.channelFailure(String message) => ExecutionResult(
        stdout: '',
        stderr: message,
        hasError: true,
        channelError: message,
      );

  /// True if there is any output to show (stdout OR stderr non-empty).
  bool get hasOutput => stdout.isNotEmpty || stderr.isNotEmpty;

  @override
  String toString() =>
      'ExecutionResult(error=$hasError, stdout.len=${stdout.length}, '
      'stderr.len=${stderr.length})';
}

// ─────────────────────────────────────────────────────────────────────────────
// PythonRunnerService
// ─────────────────────────────────────────────────────────────────────────────

/// Service that sends Python source code to the native Chaquopy interpreter
/// and returns a structured [ExecutionResult].
///
/// Usage:
/// ```dart
/// final service = PythonRunnerService();
/// final result = await service.run(code: myCode);
/// ```
class PythonRunnerService {
  // The channel name MUST match MainActivity.kt's PYTHON_CHANNEL constant.
  static const MethodChannel _channel = MethodChannel(
    'com.startup.code_et/python_engine',
  );

  /// Dart-side grace timeout – slightly longer than the Python-level 5 s +
  /// the JVM watchdog (5 + 2 = 7 s), so we never race against native cleanup.
  static const Duration _dartTimeout = Duration(seconds: 10);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Run [code] through the native Python interpreter and return the result.
  ///
  /// This method always resolves – it never throws. Channel errors, timeout,
  /// and bad arguments are all surfaced as [ExecutionResult.channelError].
  Future<ExecutionResult> run({required String code}) async {
    if (code.trim().isEmpty) {
      return ExecutionResult.channelFailure('No code to execute.');
    }

    try {
      // The channel call is async on the Dart side; the native side executes
      // Python on a background thread and returns via result.success().
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('runPython', code)
          .timeout(
        _dartTimeout,
        onTimeout: () {
          // Ask the native side to cancel and return a timeout result.
          _channel.invokeMethod<bool>('cancelExecution').ignore();
          return null;
        },
      );

      if (raw == null) {
        return ExecutionResult.channelFailure(
          '⏱  Dart-side timeout: execution exceeded ${_dartTimeout.inSeconds}s.',
        );
      }

      return _decodeResult(raw);
    } on PlatformException catch (e) {
      return ExecutionResult.channelFailure(
        '[${e.code}] ${e.message ?? 'Unknown platform error'}',
      );
    } on MissingPluginException {
      return ExecutionResult.channelFailure(
        'Python engine channel not available on this platform. '
        'Run on a physical/virtual Android device.',
      );
    } catch (e) {
      return ExecutionResult.channelFailure('Unexpected error: $e');
    }
  }

  /// Ask the native side to interrupt the currently running Python execution.
  /// Returns `true` if a running execution was cancelled, `false` otherwise.
  Future<bool> cancelExecution() async {
    try {
      final cancelled =
          await _channel.invokeMethod<bool>('cancelExecution') ?? false;
      return cancelled;
    } catch (_) {
      return false;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Safely decode the raw [Map] returned by the native channel into an
  /// [ExecutionResult], handling missing or wrongly-typed fields gracefully.
  ExecutionResult _decodeResult(Map<Object?, Object?> raw) {
    final stdout   = _safeString(raw['stdout']);
    final stderr   = _safeString(raw['stderr']);
    final hasError = raw['error'] as bool? ?? false;

    return ExecutionResult(
      stdout:   stdout,
      stderr:   stderr,
      hasError: hasError,
    );
  }

  String _safeString(Object? value) {
    if (value == null) return '';
    return value.toString();
  }
}
