// lib/features/ai_tutor/presentation/widgets/error_explanation_bottom_sheet.dart
//
// A modal bottom sheet that:
//   1. Appears automatically when the Python engine returns hasError = true.
//   2. Shows an animated loading state while the model initialises/generates.
//   3. Streams the AI's token-by-token explanation with a blinking cursor.
//   4. Falls back gracefully when the model binary is not found on-device.
//
// Show it from anywhere with:
//   ErrorExplanationBottomSheet.show(
//     context: context,
//     code:    editorContent,
//     error:   stderrText,
//   );

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/services/local_inference_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
const Color _kSheetBg    = Color(0xFF161B22);
const Color _kAccent     = Color(0xFF00E5FF);
const Color _kErrorRed   = Color(0xFFFF6B6B);
const Color _kTextNormal = Color(0xFFD4D4D4);
const Color _kTextDim    = Color(0xFF8B949E);
const Color _kDivider    = Color(0xFF21262D);

// ─────────────────────────────────────────────────────────────────────────────
// ErrorExplanationBottomSheet
// ─────────────────────────────────────────────────────────────────────────────
class ErrorExplanationBottomSheet extends StatefulWidget {
  final String code;
  final String error;

  const ErrorExplanationBottomSheet({
    super.key,
    required this.code,
    required this.error,
  });

  // ── Static factory helper ─────────────────────────────────────────────────
  static Future<void> show({
    required BuildContext context,
    required String code,
    required String error,
  }) {
    return showModalBottomSheet<void>(
      context:          context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ErrorExplanationBottomSheet(code: code, error: error),
    );
  }

  @override
  State<ErrorExplanationBottomSheet> createState() =>
      _ErrorExplanationBottomSheetState();
}

class _ErrorExplanationBottomSheetState
    extends State<ErrorExplanationBottomSheet>
    with SingleTickerProviderStateMixin {
  // ── State machine ─────────────────────────────────────────────────────────
  _SheetPhase _phase = _SheetPhase.initialising;
  String _explanation = '';
  String _errorMessage = '';
  bool _streamDone = false;

  // ── Blinking cursor animation ─────────────────────────────────────────────
  late final AnimationController _cursorCtrl;
  late final Animation<double>   _cursorAnim;

  // ── Stream subscription ───────────────────────────────────────────────────
  StreamSubscription<String>? _tokenSub;

  // ── Shared service ────────────────────────────────────────────────────────
  final LocalInferenceService _service = LocalInferenceService.instance;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Set up blinking cursor.
    _cursorCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
    _cursorAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_cursorCtrl);

    // Start the inference pipeline after the first frame so the sheet
    // animates in before any blocking call occurs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInference());
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    _tokenSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Inference pipeline
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _startInference() async {
    // ── Step 1: Init model if needed ─────────────────────────────────────────
    if (_service.state != InferenceState.ready) {
      _setPhase(_SheetPhase.initialising);

      // Determine the expected model path.  The model binary (*.task) must be
      // downloaded by the user into the app's documents directory.
      final modelPath = await _resolveModelPath();

      try {
        await _service.initModel(modelPath);
      } on InferenceException catch (e) {
        _setError(_friendlyError(e));
        return;
      } catch (e) {
        _setError('Unexpected error initialising AI tutor: $e');
        return;
      }
    }

    // ── Step 2: Stream explanation tokens ─────────────────────────────────
    _setPhase(_SheetPhase.streaming);

    try {
      final tokenStream = _service.explainError(
        code:  widget.code,
        error: widget.error,
      );

      _tokenSub = tokenStream.listen(
        (token) {
          if (mounted) {
            setState(() => _explanation += token);
          }
        },
        onError: (Object e) {
          final msg = e is InferenceException
              ? _friendlyError(e)
              : 'Token stream error: $e';
          _setError(msg);
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _streamDone = true;
              _phase      = _SheetPhase.done;
            });
            _cursorCtrl.stop();
          }
        },
        cancelOnError: true,
      );
    } on InferenceException catch (e) {
      _setError(_friendlyError(e));
    } catch (e) {
      _setError('Failed to start AI explanation: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setPhase(_SheetPhase phase) {
    if (mounted) setState(() => _phase = phase);
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _phase        = _SheetPhase.error;
        _errorMessage = msg;
      });
      _cursorCtrl.stop();
    }
  }

  /// Returns a human-friendly description for known error codes.
  String _friendlyError(InferenceException e) {
    switch (e.code) {
      case 'MODEL_NOT_FOUND':
        return '⚠️ AI model not installed.\n\n'
            'Download the 4-bit Gemma-3-1B model file and place it in the '
            'EthioCode/models/ folder on your device.';
      case 'MODEL_UNREADABLE':
        return '⚠️ Cannot read model file. Check storage permissions.';
      case 'BUSY':
        return 'Another explanation is already generating. Please wait.';
      case 'NOT_INITIALISED':
      case 'NOT_READY':
        return 'AI tutor is not ready yet. Please try again in a moment.';
      default:
        return 'AI error [${e.code}]: ${e.message}';
    }
  }

  /// Resolve where the model file should live.
  /// The app looks for `<appDocDir>/models/model.task` by convention.
  Future<String> _resolveModelPath() async {
    // The native Kotlin side resolves getFilesDir() at runtime.
    // This conventional path matches what the download manager will write to.
    return '/data/user/0/com.example.ethiocode/files/models/model.task';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      margin:      const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color:        _kSheetBg,
        borderRadius: BorderRadius.circular(20.0),
        border:       Border.all(color: _kDivider, width: 1.0),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 16,
            bottom: 20 + bottomPadding,
          ),
          child: Column(
            mainAxisSize:     MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHandle(),
              const SizedBox(height: 16),
              _buildHeader(),
              const SizedBox(height: 4),
              _buildErrorSnippet(),
              const Divider(color: _kDivider, height: 24),
              _buildBody(),
              if (_phase == _SheetPhase.done) ...[
                const SizedBox(height: 16),
                _buildDoneActions(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40, height: 4,
        decoration: BoxDecoration(
          color:        const Color(0xFF30363D),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color:        _kAccent.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_fix_high_rounded, color: _kAccent, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Tutor',
                style: TextStyle(
                  fontFamily:  'monospace',
                  fontSize:    14,
                  fontWeight:  FontWeight.w700,
                  color:       _kTextNormal,
                ),
              ),
              Text(
                _phaseLabel(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize:   10,
                  color:      _kTextDim,
                ),
              ),
            ],
          ),
        ),
        // Dismiss button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close_rounded, color: _kTextDim, size: 20),
        ),
      ],
    );
  }

  String _phaseLabel() {
    switch (_phase) {
      case _SheetPhase.initialising: return 'Loading model…';
      case _SheetPhase.streaming:    return 'Thinking…';
      case _SheetPhase.done:         return 'Explanation ready';
      case _SheetPhase.error:        return 'Error';
    }
  }

  Widget _buildErrorSnippet() {
    final display = widget.error.trim().isEmpty
        ? '(no error text)'
        : widget.error.trim().length > 120
            ? '${widget.error.trim().substring(0, 120)}…'
            : widget.error.trim();

    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:        _kErrorRed.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: _kErrorRed.withAlpha(60)),
      ),
      child: Text(
        display,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize:   11,
          color:      _kErrorRed,
          height:     1.45,
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _SheetPhase.initialising:
        return _buildLoadingState('Loading AI model into memory…');

      case _SheetPhase.streaming:
        if (_explanation.isEmpty) {
          return _buildLoadingState('Generating explanation…');
        }
        return _buildStreamingText();

      case _SheetPhase.done:
        return _buildStreamingText();

      case _SheetPhase.error:
        return _buildErrorState();
    }
  }

  Widget _buildLoadingState(String label) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color:       _kAccent,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize:   12,
                color:      _kTextDim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildStreamingText() {
    return AnimatedBuilder(
      animation: _cursorAnim,
      builder: (_, __) {
        final showCursor = !_streamDone && _cursorAnim.value > 0.5;
        return SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _explanation,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize:   13.5,
                  height:     1.6,
                  color:      _kTextNormal,
                ),
              ),
              if (showCursor)
                const TextSpan(
                  text: '▋',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize:   13.5,
                    color:      _kAccent,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          _errorMessage,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize:   12.5,
            height:     1.55,
            color:      _kErrorRed,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _phase       = _SheetPhase.initialising;
              _explanation = '';
              _errorMessage = '';
              _streamDone  = false;
            });
            _cursorCtrl.repeat(reverse: true);
            _startInference();
          },
          icon:  const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
          style: TextButton.styleFrom(
            foregroundColor: _kAccent,
            textStyle:       const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _explanation));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:         Text('Explanation copied to clipboard.'),
                duration:        Duration(seconds: 2),
                backgroundColor: Color(0xFF161B22),
              ),
            );
          },
          icon:  const Icon(Icons.copy_rounded, size: 15),
          label: const Text('Copy'),
          style: TextButton.styleFrom(
            foregroundColor: _kTextDim,
            textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon:  const Icon(Icons.check_circle_outline_rounded, size: 15),
          label: const Text('Got it'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
            backgroundColor: _kAccent,
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize:   12,
              fontWeight: FontWeight.w700,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape:   RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal phase enum
// ─────────────────────────────────────────────────────────────────────────────
enum _SheetPhase { initialising, streaming, done, error }
