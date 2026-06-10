// lib/features/workspace/presentation/widgets/output_pane.dart
//
// Placeholder for the output/execution engine.
// Designed to accept lines of text output via a ValueNotifier in the future.
// Currently renders an empty, styled pane ready for the interpreter hook-up.

import 'package:flutter/material.dart';

const Color _kOutputBg     = Color(0xFF0A0E14);
const Color _kOutputBorder = Color(0xFF21262D);
const Color _kOutputFg     = Color(0xFF484F58);

class OutputPane extends StatelessWidget {
  const OutputPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _kOutputBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tab bar ──────────────────────────────────────────────────────
          _OutputTabBar(),

          // ── Content area ─────────────────────────────────────────────────
          const Expanded(
            child: _EmptyOutputBody(),
          ),
        ],
      ),
    );
  }
}

// ── Tab bar showing "Output" and "Errors" tabs ───────────────────────────────
class _OutputTabBar extends StatefulWidget {
  @override
  State<_OutputTabBar> createState() => _OutputTabBarState();
}

class _OutputTabBarState extends State<_OutputTabBar> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height:  38.0,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(
          bottom: BorderSide(color: _kOutputBorder, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          _Tab(label: 'Output',  index: 0, selected: _selected,
               onTap: (i) => setState(() => _selected = i)),
          _Tab(label: 'Errors',  index: 1, selected: _selected,
               onTap: (i) => setState(() => _selected = i)),
          _Tab(label: 'Console', index: 2, selected: _selected,
               onTap: (i) => setState(() => _selected = i)),
          const Spacer(),
          // Clear button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: IconButton(
              icon:     const Icon(Icons.delete_sweep_outlined, size: 16),
              color:    _kOutputFg,
              tooltip:  'Clear output',
              padding:  EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                // Future: clear output lines via ValueNotifier.
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String    label;
  final int       index;
  final int       selected;
  final void Function(int) onTap;

  const _Tab({
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == selected;
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: isActive
                ? const BorderSide(color: Color(0xFF00E5FF), width: 2.0)
                : BorderSide.none,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily:  'monospace',
            fontSize:    12.0,
            fontWeight:  isActive ? FontWeight.w600 : FontWeight.w400,
            color:       isActive
                ? const Color(0xFFD4D4D4)
                : const Color(0xFF484F58),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// ── Empty state body ─────────────────────────────────────────────────────────
class _EmptyOutputBody extends StatelessWidget {
  const _EmptyOutputBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal_rounded,
            size:  36,
            color: _kOutputFg.withAlpha(120),
          ),
          const SizedBox(height: 10),
          Text(
            'Press ▶ Run to execute your code',
            style: TextStyle(
              fontFamily:  'monospace',
              fontSize:    12.0,
              color:       _kOutputFg.withAlpha(180),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
