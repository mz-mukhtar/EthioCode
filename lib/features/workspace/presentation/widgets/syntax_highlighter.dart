// lib/features/workspace/presentation/widgets/syntax_highlighter.dart
//
// Provides a custom TextEditingController that applies basic syntax
// highlighting for Python and HTML keywords using InlineSpan trees.
// Kept as a separate file so code_editor.dart stays focused.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Colour palette – all colours tuned for the dark IDE theme.
// ---------------------------------------------------------------------------
class _Palette {
  static const Color keyword = Color(0xFFCC99CD);   // violet – Python/HTML keywords
  static const Color string  = Color(0xFF7EC699);   // green  – string literals
  static const Color comment = Color(0xFF999999);   // grey   – comments
  static const Color number  = Color(0xFFF08D49);   // amber  – numeric literals
  static const Color tag     = Color(0xFFE8BF6A);   // gold   – HTML tags
  static const Color normal  = Color(0xFFD4D4D4);   // light  – plain text
}

// ---------------------------------------------------------------------------
// Token type
// ---------------------------------------------------------------------------
enum _TokenType { keyword, string, comment, number, htmlTag, normal }

// ---------------------------------------------------------------------------
// Syntax patterns – order matters; earlier patterns win.
// ---------------------------------------------------------------------------
final List<MapEntry<RegExp, _TokenType>> _patterns = [
  // Single-line Python comment
  MapEntry(RegExp(r'#[^\n]*'), _TokenType.comment),

  // HTML comment
  MapEntry(RegExp(r'<!--.*?-->', dotAll: true), _TokenType.comment),

  // HTML tags  <tag …> or </tag>
  MapEntry(RegExp(r'</?[\w!][^>]*>'), _TokenType.htmlTag),

  // Double-quoted strings (non-greedy, no newline crossing)
  MapEntry(RegExp(r'"[^"\\]*(?:\\.[^"\\]*)*"'), _TokenType.string),

  // Single-quoted strings
  MapEntry(RegExp(r"'[^'\\]*(?:\\.[^'\\]*)*'"), _TokenType.string),

  // Numeric literals
  MapEntry(RegExp(r'\b\d+(\.\d+)?\b'), _TokenType.number),

  // Python keywords
  MapEntry(
    RegExp(
      r'\b(False|None|True|and|as|assert|async|await|break|class|continue|'
      r'def|del|elif|else|except|finally|for|from|global|if|import|in|is|'
      r'lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|print|'
      r'input|range|len|int|float|str|list|dict|set|tuple|type|self|super)\b',
    ),
    _TokenType.keyword,
  ),

  // HTML / common keywords
  MapEntry(
    RegExp(
      r'\b(html|head|body|div|span|script|style|link|meta|title|header|'
      r'footer|main|section|article|nav|form|input|button|table|tr|td|th|'
      r'ul|ol|li|a|p|h1|h2|h3|h4|h5|h6|img|href|src|class|id|type|'
      r'DOCTYPE|charset|viewport)\b',
      caseSensitive: false,
    ),
    _TokenType.keyword,
  ),
];

// ---------------------------------------------------------------------------
// Tokenise a single line of plain text into (text, type) pairs.
// ---------------------------------------------------------------------------
List<MapEntry<String, _TokenType>> _tokenise(String text) {
  // We'll build a coverage list: for each character index, which type covers it.
  final types = List<_TokenType>.filled(text.length, _TokenType.normal);

  for (final entry in _patterns) {
    for (final match in entry.key.allMatches(text)) {
      for (int i = match.start; i < match.end; i++) {
        // First match wins (don't overwrite already-coloured chars).
        if (types[i] == _TokenType.normal) {
          types[i] = entry.value;
        }
      }
    }
  }

  // Collapse into runs of the same type.
  final List<MapEntry<String, _TokenType>> spans = [];
  if (text.isEmpty) return spans;

  int start = 0;
  _TokenType current = types[0];
  for (int i = 1; i < text.length; i++) {
    if (types[i] != current) {
      spans.add(MapEntry(text.substring(start, i), current));
      start = i;
      current = types[i];
    }
  }
  spans.add(MapEntry(text.substring(start), current));
  return spans;
}

// ---------------------------------------------------------------------------
// Map token type → TextStyle
// ---------------------------------------------------------------------------
TextStyle _styleFor(_TokenType t) {
  switch (t) {
    case _TokenType.keyword:
      return const TextStyle(color: _Palette.keyword, fontWeight: FontWeight.w600);
    case _TokenType.string:
      return const TextStyle(color: _Palette.string);
    case _TokenType.comment:
      return const TextStyle(color: _Palette.comment, fontStyle: FontStyle.italic);
    case _TokenType.number:
      return const TextStyle(color: _Palette.number);
    case _TokenType.htmlTag:
      return const TextStyle(color: _Palette.tag);
    case _TokenType.normal:
      return const TextStyle(color: _Palette.normal);
  }
}

// ---------------------------------------------------------------------------
// Public: build a TextSpan tree for an entire multi-line source string.
// ---------------------------------------------------------------------------
TextSpan buildHighlightedSpan(String source, TextStyle baseStyle) {
  final lines = source.split('\n');
  final List<InlineSpan> children = [];

  for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
    final line = lines[lineIdx];
    final tokens = _tokenise(line);

    for (final token in tokens) {
      children.add(TextSpan(
        text: token.key,
        style: baseStyle.merge(_styleFor(token.value)),
      ));
    }

    // Re-add the newline that split() removed (except after the last line).
    if (lineIdx < lines.length - 1) {
      children.add(TextSpan(text: '\n', style: baseStyle));
    }
  }

  return TextSpan(style: baseStyle, children: children);
}

// ---------------------------------------------------------------------------
// SyntaxHighlightingController
// ---------------------------------------------------------------------------
/// A [TextEditingController] that automatically syntax-highlights its content
/// on every change using [buildHighlightedSpan].
class SyntaxHighlightingController extends TextEditingController {
  SyntaxHighlightingController({super.text});

  static const TextStyle _baseStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14.0,
    color: _Palette.normal,
    height: 1.5,
    letterSpacing: 0.3,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final effectiveStyle = _baseStyle.merge(style);
    return buildHighlightedSpan(text, effectiveStyle);
  }
}
