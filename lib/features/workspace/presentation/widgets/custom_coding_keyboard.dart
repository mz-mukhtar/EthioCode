// lib/features/workspace/presentation/widgets/custom_coding_keyboard.dart
//
// A horizontally-scrollable custom coding keyboard row that:
//   • Injects symbols at the exact cursor position (TextSelection).
//   • Handles every edge-case: empty text, cursor at position 0, cursor at
//     the last character, and a non-collapsed (highlighted) selection.
//   • Preserves focus on the TextField after every key tap so the OS keyboard
//     never disappears.
//   • The special [Tab] key inserts 4 spaces to replicate IDE tab behaviour.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'syntax_highlighter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Key model
// ─────────────────────────────────────────────────────────────────────────────
class _KeyDef {
  final String label;     // what is shown on the key face
  final String insert;    // what is inserted into the text field
  final bool   isWide;    // whether to give it extra horizontal room

  const _KeyDef(this.label, this.insert, {this.isWide = false});
}

// All required keys in display order.
const List<_KeyDef> _keys = [
  _KeyDef('Tab',  '    ', isWide: true),   // 4 spaces
  _KeyDef('<',    '<'),
  _KeyDef('>',    '>'),
  _KeyDef('{',    '{'),
  _KeyDef('}',    '}'),
  _KeyDef('[',    '['),
  _KeyDef(']',    ']'),
  _KeyDef('(',    '('),
  _KeyDef(')',    ')'),
  _KeyDef('=',    '='),
  _KeyDef('"',    '"'),
  _KeyDef("'",    "'"),
  _KeyDef(';',    ';'),
  _KeyDef(':',    ':'),
  _KeyDef('_',    '_'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Colours
// ─────────────────────────────────────────────────────────────────────────────
const Color _kKeyboardBg   = Color(0xFF161B22);
const Color _kKeyBg        = Color(0xFF21262D);
const Color _kKeyBgPressed = Color(0xFF30363D);
const Color _kKeyFg        = Color(0xFFD4D4D4);
const Color _kTabKeyFg     = Color(0xFF00E5FF);
const Color _kTabKeyBg     = Color(0xFF0D2137);
const Color _kDivider      = Color(0xFF21262D);

// ─────────────────────────────────────────────────────────────────────────────
// CustomCodingKeyboard
// ─────────────────────────────────────────────────────────────────────────────
class CustomCodingKeyboard extends StatelessWidget {
  /// The controller shared with [CodeEditor].
  final SyntaxHighlightingController controller;

  /// The focus node of the [CodeEditor]'s TextField.  We must call
  /// [focusNode.requestFocus()] after injecting text to prevent the OS keyboard
  /// from collapsing.
  final FocusNode focusNode;

  const CustomCodingKeyboard({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  // ── text insertion logic ──────────────────────────────────────────────────

  /// Inserts [chars] at the current cursor / replaces the current selection.
  ///
  /// Edge cases handled:
  ///   1. Controller has no valid selection  → append to end.
  ///   2. Cursor at position 0              → prepend to text.
  ///   3. Cursor at text.length             → append to text.
  ///   4. Non-collapsed (highlighted) text  → replace the selected range.
  ///   5. Normal collapsed cursor           → insert at cursor offset.
  void _insertAt(String chars) {
    final text      = controller.text;
    final selection = controller.selection;

    // ── Guard: no valid selection → append ──────────────────────────────────
    if (!selection.isValid) {
      final newText = text + chars;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      focusNode.requestFocus();
      return;
    }

    final int start = selection.start.clamp(0, text.length);
    final int end   = selection.end.clamp(0, text.length);

    // Build the new text by replacing [start, end) with [chars].
    final String newText =
        text.substring(0, start) + chars + text.substring(end);

    // Place the cursor right after the inserted character(s).
    final int newCursorOffset = (start + chars.length).clamp(0, newText.length);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorOffset),
    );

    // Restore focus so the OS keyboard stays visible.
    focusNode.requestFocus();

    // Provide haptic feedback for a premium feel on real devices.
    HapticFeedback.selectionClick();
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48.0,
      decoration: const BoxDecoration(
        color: _kKeyboardBg,
        border: Border(
          top: BorderSide(color: _kDivider, width: 1.0),
        ),
      ),
      child: ScrollConfiguration(
        behavior: _NoGlowScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
          itemCount: _keys.length,
          separatorBuilder: (_, __) => const SizedBox(width: 5.0),
          itemBuilder: (context, index) {
            final key = _keys[index];
            return _KeyButton(
              keyDef: key,
              onTap:  () => _insertAt(key.insert),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual key button with press-state animation
// ─────────────────────────────────────────────────────────────────────────────
class _KeyButton extends StatefulWidget {
  final _KeyDef keyDef;
  final VoidCallback onTap;

  const _KeyButton({required this.keyDef, required this.onTap});

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double>   _scaleAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    setState(() => _pressed = true);
    _animCtrl.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    _animCtrl.reverse().then((_) {
      if (mounted) setState(() => _pressed = false);
    });
    widget.onTap();
  }

  void _handleTapCancel() {
    _animCtrl.reverse();
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final isTab = widget.keyDef.label == 'Tab';

    return GestureDetector(
      onTapDown:   _handleTapDown,
      onTapUp:     _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          width:  isTab ? 58.0 : 36.0,
          decoration: BoxDecoration(
            color: _pressed
                ? _kKeyBgPressed
                : (isTab ? _kTabKeyBg : _kKeyBg),
            borderRadius: BorderRadius.circular(6.0),
            border: isTab
                ? Border.all(color: const Color(0xFF00E5FF), width: 0.8)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.keyDef.label,
            style: TextStyle(
              fontFamily:  'monospace',
              fontSize:     isTab ? 11.5 : 14.0,
              fontWeight:   FontWeight.w600,
              color:        isTab ? _kTabKeyFg : _kKeyFg,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Suppress the overscroll glow on the horizontal list.
// ─────────────────────────────────────────────────────────────────────────────
class _NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
