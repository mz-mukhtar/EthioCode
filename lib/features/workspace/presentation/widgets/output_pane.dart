// lib/features/workspace/presentation/widgets/output_pane.dart
//
// Renders execution results from the Python engine and hosts the WebView
// preview tab. Driven by a ValueNotifier<OutputPaneState> supplied from
// WorkspacePage – no rebuilds outside the pane boundary.

import 'package:flutter/material.dart';
import '../../domain/services/python_runner_service.dart';
import 'web_preview_pane.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OutputPaneState – immutable snapshot passed via ValueNotifier
// ─────────────────────────────────────────────────────────────────────────────
enum OutputTab { output, errors, preview }

class OutputPaneState {
  final ExecutionResult? result;
  final bool isRunning;
  final String htmlSource;
  final OutputTab activeTab;

  const OutputPaneState({
    this.result,
    this.isRunning   = false,
    this.htmlSource  = '',
    this.activeTab   = OutputTab.output,
  });

  OutputPaneState copyWith({
    ExecutionResult? result,
    bool? isRunning,
    String? htmlSource,
    OutputTab? activeTab,
  }) => OutputPaneState(
    result:    result    ?? this.result,
    isRunning: isRunning ?? this.isRunning,
    htmlSource: htmlSource ?? this.htmlSource,
    activeTab:  activeTab  ?? this.activeTab,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Colours
// ─────────────────────────────────────────────────────────────────────────────
const Color _kOutputBg  = Color(0xFF0A0E14);
const Color _kTabBarBg  = Color(0xFF0D1117);
const Color _kBorder    = Color(0xFF21262D);
const Color _kFgDim     = Color(0xFF484F58);
const Color _kFgActive  = Color(0xFF00E5FF);
const Color _kFgNormal  = Color(0xFFD4D4D4);
const Color _kFgError   = Color(0xFFFF6B6B);

// ─────────────────────────────────────────────────────────────────────────────
// OutputPane
// ─────────────────────────────────────────────────────────────────────────────
class OutputPane extends StatefulWidget {
  final ValueNotifier<OutputPaneState> stateNotifier;

  const OutputPane({super.key, required this.stateNotifier});

  @override
  State<OutputPane> createState() => _OutputPaneState();
}

class _OutputPaneState extends State<OutputPane> {
  final WebPreviewPaneController _previewCtrl = WebPreviewPaneController();

  @override
  void dispose() {
    _previewCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OutputPaneState>(
      valueListenable: widget.stateNotifier,
      builder: (context, state, _) {
        // Auto-reload WebView when htmlSource changes.
        if (state.activeTab == OutputTab.preview &&
            state.htmlSource.isNotEmpty) {
          _previewCtrl.reload(state.htmlSource);
        }

        return Container(
          color: _kOutputBg,
          child: Column(
            children: [
              _TabBar(
                activeTab:    state.activeTab,
                isRunning:    state.isRunning,
                hasError:     state.result?.hasError ?? false,
                onTabChanged: (tab) {
                  widget.stateNotifier.value =
                      state.copyWith(activeTab: tab);
                },
                onClear: () {
                  widget.stateNotifier.value = const OutputPaneState();
                  _previewCtrl.clear();
                },
              ),
              Expanded(child: _buildBody(state)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(OutputPaneState state) {
    switch (state.activeTab) {
      case OutputTab.output:
        return _OutputBody(
          result:    state.result,
          isRunning: state.isRunning,
          showErrors: false,
        );
      case OutputTab.errors:
        return _OutputBody(
          result:    state.result,
          isRunning: state.isRunning,
          showErrors: true,
        );
      case OutputTab.preview:
        return WebPreviewPane(
          htmlSource: state.htmlSource,
          controller: _previewCtrl,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab bar
// ─────────────────────────────────────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final OutputTab activeTab;
  final bool isRunning;
  final bool hasError;
  final void Function(OutputTab) onTabChanged;
  final VoidCallback onClear;

  const _TabBar({
    required this.activeTab,
    required this.isRunning,
    required this.hasError,
    required this.onTabChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38.0,
      decoration: const BoxDecoration(
        color: _kTabBarBg,
        border: Border(bottom: BorderSide(color: _kBorder, width: 1.0)),
      ),
      child: Row(
        children: [
          _Tab(
            label:    'Output',
            tab:      OutputTab.output,
            active:   activeTab,
            onTap:    onTabChanged,
          ),
          _Tab(
            label:    'Errors',
            tab:      OutputTab.errors,
            active:   activeTab,
            badge:    hasError,
            onTap:    onTabChanged,
          ),
          _Tab(
            label:    'Preview',
            tab:      OutputTab.preview,
            active:   activeTab,
            onTap:    onTabChanged,
          ),
          const Spacer(),
          // Running indicator
          if (isRunning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: _kFgActive,
                ),
              ),
            ),
          // Clear button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: IconButton(
              icon:        const Icon(Icons.delete_sweep_outlined, size: 16),
              color:       _kFgDim,
              tooltip:     'Clear output',
              padding:     EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed:   onClear,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final OutputTab tab;
  final OutputTab active;
  final bool badge;
  final void Function(OutputTab) onTap;

  const _Tab({
    required this.label,
    required this.tab,
    required this.active,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = tab == active;
    return GestureDetector(
      onTap: () => onTap(tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:  const EdgeInsets.symmetric(horizontal: 14.0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: isActive
                ? const BorderSide(color: _kFgActive, width: 2.0)
                : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily:   'monospace',
                fontSize:     12.0,
                fontWeight:   isActive ? FontWeight.w600 : FontWeight.w400,
                color:        isActive ? _kFgNormal : _kFgDim,
                letterSpacing: 0.2,
              ),
            ),
            if (badge) ...[
              const SizedBox(width: 5),
              Container(
                width:  6, height: 6,
                decoration: const BoxDecoration(
                  color: _kFgError,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Output / Error body
// ─────────────────────────────────────────────────────────────────────────────
class _OutputBody extends StatefulWidget {
  final ExecutionResult? result;
  final bool isRunning;
  final bool showErrors;

  const _OutputBody({
    required this.result,
    required this.isRunning,
    required this.showErrors,
  });

  @override
  State<_OutputBody> createState() => _OutputBodyState();
}

class _OutputBodyState extends State<_OutputBody> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isRunning && widget.result == null) {
      return const Center(
        child: Text(
          'Running…',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize:   12.0,
            color:      _kFgDim,
          ),
        ),
      );
    }

    if (widget.result == null) return _emptyState();

    final text = widget.showErrors ? widget.result!.stderr : widget.result!.stdout;
    final isEmpty = text.trim().isEmpty;

    if (isEmpty) {
      return Center(
        child: Text(
          widget.showErrors ? 'No errors.' : 'No output.',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize:   12.0,
            color:      _kFgDim,
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(12.0),
        child: SelectableText(
          text,
          style: TextStyle(
            fontFamily:    'monospace',
            fontSize:      12.5,
            height:        1.55,
            color:         widget.showErrors ? _kFgError : _kFgNormal,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal_rounded,
            size:  36,
            color: _kFgDim.withAlpha(120),
          ),
          const SizedBox(height: 10),
          Text(
            'Press ▶ Run to execute your code',
            style: TextStyle(
              fontFamily:    'monospace',
              fontSize:      12.0,
              color:         _kFgDim.withAlpha(180),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
