// lib/features/workspace/presentation/pages/workspace_page.dart
//
// Root page of the coding workspace. Assembles:
//   • An app bar with file name, run/stop buttons, and settings button.
//   • A vertical split-view between the CodeEditor (top) and OutputPane (bottom)
//     separated by a draggable divider handle.
//   • A sticky CustomCodingKeyboard row anchored directly above the OS keyboard
//     using resizeToAvoidBottomInset – it never scrolls away.
//
// Execution flow:
//   1. User presses ▶ Run.
//   2. WorkspacePage detects whether the code is HTML or Python.
//   3. For Python → calls PythonRunnerService.run() and pushes the
//      ExecutionResult into the OutputPaneState notifier.
//   4. For HTML   → sets htmlSource on the OutputPaneState notifier,
//      auto-switching to the Preview tab.
//   5. The Stop (■) button calls PythonRunnerService.cancelExecution().

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/code_editor.dart';
import '../widgets/custom_coding_keyboard.dart';
import '../widgets/output_pane.dart';
import '../widgets/syntax_highlighter.dart';
import '../../domain/services/python_runner_service.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../projects/domain/models/project.dart';
import '../../../projects/data/repositories/project_repository.dart';
import '../../../projects/data/repositories/snapshot_repository.dart';
import '../../../../core/session/session_manager.dart';
import '../../../../core/database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const double _kDividerHeight     = 28.0;
const double _kMinSplitRatio     = 0.20;
const double _kMaxSplitRatio     = 0.85;
const double _kDefaultSplitRatio = 0.60;

// ─────────────────────────────────────────────────────────────────────────────
// WorkspacePage
// ─────────────────────────────────────────────────────────────────────────────
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  // ── Editor state ──────────────────────────────────────────────────────────
  final SyntaxHighlightingController _controller = SyntaxHighlightingController();
  final FocusNode _focusNode = FocusNode();

  // ── Persistence & Session ─────────────────────────────────────────────────
  final SessionManager _sessionManager = SessionManager();
  final ProjectRepository _projectRepo = ProjectRepository();
  final SnapshotRepository _snapshotRepo = SnapshotRepository();
  
  Project? _activeProject;
  Timer? _autosaveTimer;
  bool _isLoading = true;

  // ── Split-view ────────────────────────────────────────────────────────────
  final ValueNotifier<double> _splitRatio =
      ValueNotifier<double>(_kDefaultSplitRatio);
  double _dragStartRatio = _kDefaultSplitRatio;
  double _dragStartDy    = 0.0;

  // ── Execution engine ──────────────────────────────────────────────────────
  final PythonRunnerService _pythonRunner = PythonRunnerService();
  final ValueNotifier<OutputPaneState> _outputState =
      ValueNotifier<OutputPaneState>(const OutputPaneState());

  // ── Language detection ────────────────────────────────────────────────────
  /// True when the editor content looks like HTML.
  bool get _isHtml {
    final text = _controller.text.trimLeft();
    return text.startsWith('<!') ||
        text.toLowerCase().startsWith('<html') ||
        text.toLowerCase().startsWith('<head') ||
        text.toLowerCase().startsWith('<body');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    
    _controller.addListener(_onTextChanged);
    _loadSession();
  }

  Future<void> _loadSession() async {
    
    final lastProjId = await _sessionManager.getLastProjectId();
    Project? p;
    if (lastProjId != null) {
      
      p = await _projectRepo.getProject(lastProjId);
    }
    
    p ??= await _projectRepo.createProject(
      title: 'My First Python Project',
      language: 'python',
      currentCode: _kWelcomeSnippet,
    );

    
    await _openProject(p);
  }

  Future<void> _openProject(Project project) async {
    // Save current cursor if there's an active project before switching
    if (_activeProject != null) {
      await _sessionManager.setLastCursorPosition(_controller.selection.baseOffset);
    }

    // Update active project
    project = project.copyWith(lastOpenedAt: DatabaseHelper.nowMs());
    await _projectRepo.updateProject(project);
    await _sessionManager.setLastProjectId(project.id);
    
    _controller.text = project.currentCode;

    // Restore cursor position if this was the last active project
    final lastCursor = await _sessionManager.getLastCursorPosition();
    if (lastCursor >= 0 && lastCursor <= _controller.text.length) {
      _controller.selection = TextSelection.collapsed(offset: lastCursor);
    } else {
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }

    setState(() {
      _activeProject = project;
      _isLoading = false;
    });
  }

  void _onTextChanged() {
    if (_isLoading || _activeProject == null) return;
    
    // Debounce save for 1000ms
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1000), _saveCodeToDb);
  }

  Future<void> _saveCodeToDb() async {
    if (_activeProject == null) return;
    
    final newCode = _controller.text;
    if (_activeProject!.currentCode == newCode) return; // No change

    final updated = _activeProject!.copyWith(
      currentCode: newCode,
      updatedAt: DatabaseHelper.nowMs(),
    );
    _activeProject = updated;
    await _projectRepo.updateProject(updated);
    
    // Save cursor position implicitly during autosaves
    final offset = _controller.selection.baseOffset;
    if (offset >= 0) {
      await _sessionManager.setLastCursorPosition(offset);
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    // Final sync
    _saveCodeToDb().ignore();
    _sessionManager.setLastCursorPosition(_controller.selection.baseOffset).ignore();
    
    _controller.dispose();
    _focusNode.dispose();
    _splitRatio.dispose();
    _outputState.dispose();
    super.dispose();
  }

  // ── Run ───────────────────────────────────────────────────────────────────
  Future<void> _handleRun() async {
    // Unfocus so the keyboard doesn't interfere with the scrollable output.
    _focusNode.unfocus();

    final code = _controller.text;
    if (code.trim().isEmpty) return;

    if (_isHtml) {
      // HTML mode: send directly to the WebView preview.
      _outputState.value = OutputPaneState(
        htmlSource: code,
        activeTab:  OutputTab.preview,
        isRunning:  false,
      );
      return;
    }

    // Python mode.
    _outputState.value = _outputState.value.copyWith(
      isRunning: true,
      result:    null,
      activeTab: OutputTab.output,
    );

    // Save project and capture snapshot BEFORE execution
    await _saveCodeToDb();
    if (_activeProject != null) {
      await _snapshotRepo.insertSnapshot(
        projectId: _activeProject!.id,
        codeContent: code,
      );
    }

    final result = await _pythonRunner.run(code: code);

    if (!mounted) return;

    _outputState.value = _outputState.value.copyWith(
      isRunning: false,
      result:    result,
      // Auto-switch to errors tab when there's a problem and no stdout.
      activeTab: (result.hasError && result.stdout.isEmpty)
          ? OutputTab.errors
          : OutputTab.output,
    );
  }

  Future<void> _handleStop() async {
    await _pythonRunner.cancelExecution();
    if (!mounted) return;
    _outputState.value = _outputState.value.copyWith(isRunning: false);
  }

  // ── Split-view drag ───────────────────────────────────────────────────────
  void _onDragStart(DragStartDetails d, double h) {
    _dragStartRatio = _splitRatio.value;
    _dragStartDy    = d.globalPosition.dy;
  }

  void _onDragUpdate(DragUpdateDetails d, double h) {
    if (h <= 0) return;
    _splitRatio.value =
        (_dragStartRatio + (d.globalPosition.dy - _dragStartDy) / h)
            .clamp(_kMinSplitRatio, _kMaxSplitRatio);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0D1117),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Split-view ────────────────────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final total = constraints.maxHeight;
                return ValueListenableBuilder<double>(
                  valueListenable: _splitRatio,
                  builder: (context, ratio, _) {
                    final editorH =
                        (total * ratio - _kDividerHeight / 2).clamp(0.0, total);
                    final outputH =
                        (total * (1 - ratio) - _kDividerHeight / 2)
                            .clamp(0.0, total);

                    return Column(
                      children: [
                        SizedBox(
                          height: editorH,
                          child: CodeEditor(
                            controller: _controller,
                            focusNode:  _focusNode,
                          ),
                        ),
                        _buildDragHandle(total),
                        SizedBox(
                          height: outputH,
                          child: OutputPane(
                            stateNotifier: _outputState,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ── Sticky custom keyboard ────────────────────────────────────────
          CustomCodingKeyboard(
            controller: _controller,
            focusNode:  _focusNode,
          ),
        ],
      ),
    );
  }

  // ── Project Switcher ──────────────────────────────────────────────────────
  Future<void> _showProjectSwitcher() async {
    final projects = await _projectRepo.getProjects();
    
    if (!mounted) return;
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2329),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Projects',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          final p = await _projectRepo.createProject(
                            title: 'Project \${projects.length + 1}',
                            language: 'python',
                            currentCode: _kWelcomeSnippet,
                          );
                          nav.pop();
                          _openProject(p);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final p = projects[index];
                      final isActive = _activeProject?.id == p.id;
                      
                      return ListTile(
                        leading: Icon(
                          Icons.description_rounded,
                          color: isActive ? const Color(0xFF00E5FF) : Colors.grey,
                        ),
                        title: Text(
                          p.title,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey[300],
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          "Last opened: \${DateTime.fromMillisecondsSinceEpoch(p.lastOpenedAt).toString().split('.').first}",
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () async {
                            if (projects.length <= 1) return; // Don't delete last project
                            final nav = Navigator.of(context);
                            await _projectRepo.deleteProject(p.id);
                            if (isActive) {
                              nav.pop();
                              _loadSession(); // Load another project
                            } else {
                              setSheetState(() {
                                projects.removeAt(index);
                              });
                            }
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _openProject(p);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor:  const Color(0xFF161B22),
      surfaceTintColor: Colors.transparent,
      elevation:        0,
      titleSpacing:     16.0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: InkWell(
          onTap: _showProjectSwitcher,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              color:        const Color(0xFF00E5FF).withAlpha(30),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              color: Color(0xFF00E5FF),
              size:  20,
            ),
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _activeProject?.title ?? 'Loading...',
            style: const TextStyle(
              fontFamily:    'monospace',
              fontSize:      14.0,
              fontWeight:    FontWeight.w600,
              color:         Color(0xFFD4D4D4),
              letterSpacing: 0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          const Text(
            'Python · EthioCode',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize:   10.0,
              color:      Color(0xFF484F58),
            ),
          ),
        ],
      ),
      actions: [
        // ── Stop button (visible only while running) ──────────────────────
        ValueListenableBuilder<OutputPaneState>(
          valueListenable: _outputState,
          builder: (_, state, __) {
            if (!state.isRunning) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: TextButton.icon(
                onPressed: _handleStop,
                icon:  const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Stop'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF8B2020),
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize:   13.0,
                    fontWeight: FontWeight.w700,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  shape:   const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8.0)),
                  ),
                ),
              ),
            );
          },
        ),
        // ── Run button ─────────────────────────────────────────────────────
        ValueListenableBuilder<OutputPaneState>(
          valueListenable: _outputState,
          builder: (_, state, __) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: TextButton.icon(
                onPressed: state.isRunning ? null : _handleRun,
                icon:  const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Run'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black,
                  backgroundColor: state.isRunning
                      ? const Color(0xFF00E5FF).withAlpha(90)
                      : const Color(0xFF00E5FF),
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
            );
          },
        ),
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
          },
          icon: const Icon(Icons.tune_rounded, color: Color(0xFF8B949E)),
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

  // ── Drag handle ───────────────────────────────────────────────────────────
  Widget _buildDragHandle(double h) {
    return GestureDetector(
      behavior:             HitTestBehavior.opaque,
      onVerticalDragStart:  (d) => _onDragStart(d, h),
      onVerticalDragUpdate: (d) => _onDragUpdate(d, h),
      child: Container(
        height: _kDividerHeight,
        color:  const Color(0xFF0D1117),
        child: Center(
          child: Container(
            height: 4.0,
            width:  48.0,
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
// Welcome snippet
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
