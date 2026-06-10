// lib/features/workspace/presentation/widgets/code_editor.dart
//
// A production-grade code editor widget featuring:
//   • SyntaxHighlightingController for Python/HTML keyword colouring.
//   • Dynamic line numbers on the left margin synced to the scroll position.
//   • Shared ScrollController between the line-number gutter and the TextField.
//   • Accepts an external TextEditingController so WorkspacePage can share it
//     with the CustomCodingKeyboard for cursor-precise symbol injection.

import 'package:flutter/material.dart';
import 'syntax_highlighter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const double _kFontSize   = 14.0;
const double _kLineHeight = 1.5;
const double _kLinePixels = _kFontSize * _kLineHeight; // ≈ 21 px per line
const double _kGutterWidth = 52.0;
const Color  _kGutterBg  = Color(0xFF161B22);
const Color  _kEditorBg  = Color(0xFF0D1117);
const Color  _kGutterFg  = Color(0xFF484F58);
const Color  _kGutterFgActive = Color(0xFF8B949E);
const Color  _kCursorColor    = Color(0xFF00E5FF);
const Color  _kSelectionColor = Color(0x4400E5FF);

// ─────────────────────────────────────────────────────────────────────────────
// CodeEditor widget
// ─────────────────────────────────────────────────────────────────────────────
class CodeEditor extends StatefulWidget {
  /// The controller holds both the text content and the cursor/selection.
  /// Passed in from [WorkspacePage] so [CustomCodingKeyboard] can share it.
  final SyntaxHighlightingController controller;

  /// FocusNode shared with [WorkspacePage] so WorkspacePage can request focus
  /// programmatically (e.g. after a keyboard key tap).
  final FocusNode focusNode;

  const CodeEditor({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  // ── scroll controllers ────────────────────────────────────────────────────
  /// Primary scroll controller attached to the TextField's scrollable.
  final ScrollController _editorScroll   = ScrollController();

  /// Secondary controller for the gutter; kept in sync manually.
  final ScrollController _gutterScroll   = ScrollController();

  // ── state ─────────────────────────────────────────────────────────────────
  int _lineCount  = 1;
  int _activeLine = 1; // 1-based line of the cursor

  // ── lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _lineCount = _countLines(widget.controller.text);
    widget.controller.addListener(_onTextChanged);
    _editorScroll.addListener(_syncGutterToEditor);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _editorScroll.removeListener(_syncGutterToEditor);
    _editorScroll.dispose();
    _gutterScroll.dispose();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Count newlines + 1 to get total line count.
  int _countLines(String text) {
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  /// Derive the 1-based line number of the cursor from [TextEditingController].
  int _cursorLine(String text, int cursorOffset) {
    if (cursorOffset <= 0) return 1;
    final safeOffset = cursorOffset.clamp(0, text.length);
    return '\n'.allMatches(text.substring(0, safeOffset)).length + 1;
  }

  void _onTextChanged() {
    final newCount  = _countLines(widget.controller.text);
    final selection = widget.controller.selection;
    final newActive = selection.isValid
        ? _cursorLine(widget.controller.text, selection.baseOffset)
        : _activeLine;

    // Only rebuild if something changed to avoid gratuitous frames.
    if (newCount != _lineCount || newActive != _activeLine) {
      setState(() {
        _lineCount  = newCount;
        _activeLine = newActive;
      });
    }
  }

  /// Keep the gutter scrolled to the same vertical offset as the editor.
  void _syncGutterToEditor() {
    if (!_gutterScroll.hasClients) return;
    final offset = _editorScroll.offset.clamp(
      _gutterScroll.position.minScrollExtent,
      _gutterScroll.position.maxScrollExtent,
    );
    if ((_gutterScroll.offset - offset).abs() > 0.5) {
      _gutterScroll.jumpTo(offset);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kEditorBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGutter(),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFF21262D),
          ),
          Expanded(child: _buildTextField()),
        ],
      ),
    );
  }

  // ── gutter ────────────────────────────────────────────────────────────────
  Widget _buildGutter() {
    return Container(
      width: _kGutterWidth,
      color: _kGutterBg,
      child: ScrollConfiguration(
        // Make the gutter non-interactive (the editor scroll drives it).
        behavior: _NoScrollbarBehavior(),
        child: ListView.builder(
          controller: _gutterScroll,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
          itemCount: _lineCount,
          itemExtent: _kLinePixels,
          itemBuilder: (context, index) {
            final lineNum   = index + 1;
            final isActive  = lineNum == _activeLine;
            return Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10.0),
                child: Text(
                  '$lineNum',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize:   _kFontSize - 1,
                    height:     1.0,
                    color:      isActive ? _kGutterFgActive : _kGutterFg,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── text field ────────────────────────────────────────────────────────────
  Widget _buildTextField() {
    return TextField(
      controller:   widget.controller,
      focusNode:    widget.focusNode,
      scrollController: _editorScroll,
      maxLines:     null,           // unbounded vertical
      expands:      true,           // fills available height from parent
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      autocorrect:  false,
      enableSuggestions: false,
      style: const TextStyle(
        fontFamily:    'monospace',
        fontSize:      _kFontSize,
        height:        _kLineHeight,
        color:         Color(0xFFD4D4D4),
        letterSpacing: 0.3,
      ),
      cursorColor:  _kCursorColor,
      cursorWidth:  2.0,
      selectionControls: materialTextSelectionControls,
      decoration: const InputDecoration(
        border:          InputBorder.none,
        contentPadding:  EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
        isDense:         true,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: suppress the default scrollbar on the gutter ListView so the gutter
// never shows a visible scrollbar of its own.
// ─────────────────────────────────────────────────────────────────────────────
class _NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
