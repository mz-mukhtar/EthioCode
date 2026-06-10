// lib/features/workspace/presentation/pages/workspace_page.dart
//
// Root page of the coding workspace. Assembles:
//   • An app bar with file name, run button, and settings button.
//   • A vertical split-view between the CodeEditor (top) and OutputPane (bottom)
//     separated by a draggable divider handle.
//   • A sticky CustomCodingKeyboard row anchored directly above the OS keyboard
//     using [MediaQuery.viewInsetsOf] – it never scrolls away.
//
// State management uses a single [ValueNotifier<double>] for the split ratio
// (kept between 0.25 and 0.80) – no heavy third-party library needed.
//
// The layout uses [LayoutBuilder] to know the exact available height after
// the OS keyboard has inset the view, preventing all overflow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/code_editor.dart';
import '../widgets/custom_coding_keyboard.dart';
import '../widgets/output_pane.dart';
import '../widgets/syntax_highlighter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const double _kDividerHeight     = 28.0;  // touch-target height of the drag handle
const double _kMinSplitRatio     = 0.20;  // editor cannot be smaller than 20 %
const double _kMaxSplitRatio     = 0.85;  // editor cannot be larger than 85 %
const double _kDefaultSplitRatio = 0.60;  // initial: 60 % editor / 40 % output
const double _kKeyboardRowHeight = 48.0;

// ─────────────────────────────────────────────────────────────────────────────
// WorkspacePage
// ─────────────────────────────────────────────────────────────────────────────
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  // ── shared state ──────────────────────────────────────────────────────────
  /// The text controller is shared with both CodeEditor and CustomCodingKeyboard
  /// so the keyboard can inject text at the current cursor position.
  final SyntaxHighlightingController _controller =
      SyntaxHighlightingController(text: _kWelcomeSnippet);

  /// The focus node is shared so the keyboard row can restore focus after a tap
  /// without collapsing the OS keyboard.
  final FocusNode _focusNode = FocusNode();

  /// Ratio of the total available height that the editor pane occupies.
  final ValueNotifier<double> _splitRatio =
      ValueNotifier<double>(_kDefaultSplitRatio);

  // Track drag start values to compute delta correctly.
  double _dragStartRatio = _kDefaultSplitRatio;
  double _dragStartDy    = 0.0;

  // ── lifecycle ────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _splitRatio.dispose();
    super.dispose();
  }

  // ── drag handle callbacks ─────────────────────────────────────────────────
  void _onDragStart(DragStartDetails details, double availableHeight) {
    _dragStartRatio = _splitRatio.value;
    _dragStartDy    = details.globalPosition.dy;
  }

  void _onDragUpdate(DragUpdateDetails details, double availableHeight) {
    if (availableHeight <= 0) return;
    final delta = details.globalPosition.dy - _dragStartDy;
    final newRatio = (_dragStartRatio + delta / availableHeight)
        .clamp(_kMinSplitRatio, _kMaxSplitRatio);
    _splitRatio.value = newRatio;
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Keep the status bar visible and tinted to match the dark IDE theme.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:           Colors.transparent,
      statusBarBrightness:      Brightness.dark,
      statusBarIconBrightness:  Brightness.light,
    ));

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0D1117),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── split-view area ──────────────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // constraints.maxHeight is the height available AFTER the OS
                // keyboard has inset the view (because resizeToAvoidBottomInset
                // is true). The split is computed from this true available area.
                final totalHeight = constraints.maxHeight;

                return ValueListenableBuilder<double>(
                  valueListenable: _splitRatio,
                  builder: (context, ratio, _) {
                    final editorHeight =
                        (totalHeight * ratio - _kDividerHeight / 2)
                            .clamp(0.0, totalHeight);
                    final outputHeight =
                        (totalHeight * (1 - ratio) - _kDividerHeight / 2)
                            .clamp(0.0, totalHeight);

                    return Column(
                      children: [
                        // ── Editor pane ──────────────────────────────────
                        SizedBox(
                          height: editorHeight,
                          child: CodeEditor(
                            controller: _controller,
                            focusNode:  _focusNode,
                          ),
                        ),

                        // ── Draggable divider ─────────────────────────────
                        _buildDragHandle(totalHeight),

                        // ── Output pane ───────────────────────────────────
                        SizedBox(
                          height: outputHeight,
                          child: const OutputPane(),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ── Sticky custom keyboard row ────────────────────────────────────
          CustomCodingKeyboard(
            controller: _controller,
            focusNode:  _focusNode,
          ),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor:     const Color(0xFF161B22),
      surfaceTintColor:    Colors.transparent,
      elevation:           0,
      titleSpacing:        16.0,
      leading: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Container(
          decoration: BoxDecoration(
            color:        const Color(0xFF00E5FF).withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.code_rounded,
            color: Color(0xFF00E5FF),
            size:  20,
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'main.py',
            style: TextStyle(
              fontFamily:  'monospace',
              fontSize:    14.0,
              fontWeight:  FontWeight.w600,
              color:       Color(0xFFD4D4D4),
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: 1),
          Text(
            'Python · EthioCode',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize:    10.0,
              color:      Color(0xFF484F58),
            ),
          ),
        ],
      ),
      actions: [
        // ── Run button ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: TextButton.icon(
            onPressed: () {
              // TODO(engine): wire to interpreter/runner when implemented.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('▶  Run engine coming soon!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Color(0xFF161B22),
                ),
              );
            },
            icon:  const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Run'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor: const Color(0xFF00E5FF),
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize:   13.0,
                fontWeight: FontWeight.w700,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              shape:   RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
          ),
        ),
        // ── Settings icon ──────────────────────────────────────────────────
        IconButton(
          onPressed: () {
            // TODO: open settings drawer.
          },
          icon: const Icon(
            Icons.tune_rounded,
            color: Color(0xFF8B949E),
          ),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 4),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1.0),
        child: Divider(height: 1, thickness: 1, color: Color(0xFF21262D)),
      ),
    );
  }

  // ── Drag handle widget ────────────────────────────────────────────────────
  Widget _buildDragHandle(double availableHeight) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart:  (d) => _onDragStart(d, availableHeight),
      onVerticalDragUpdate: (d) => _onDragUpdate(d, availableHeight),
      child: Container(
        height: _kDividerHeight,
        color:  const Color(0xFF0D1117),
        child: Center(
          child: Container(
            height:       4.0,
            width:        48.0,
            decoration: BoxDecoration(
              color:        const Color(0xFF30363D),
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Welcome snippet – shown when the IDE first opens.
// ─────────────────────────────────────────────────────────────────────────────
const String _kWelcomeSnippet = '''# EthioCode – Python Playground
# Welcome! Start typing your code below.

def greet(name):
    """Return a personalised greeting."""
    return f"Selam, {name}! ሠላም ነው?"

def main():
    students = ["Abebe", "Tigist", "Dawit"]
    for student in students:
        print(greet(student))

if __name__ == "__main__":
    main()
''';
