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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import '../../../projects/data/services/project_export_service.dart';
import '../widgets/code_editor.dart';
import '../widgets/custom_coding_keyboard.dart';
import '../widgets/output_pane.dart';
import '../widgets/syntax_highlighter.dart';
import '../../domain/services/python_runner_service.dart';
import '../../domain/services/web_project_builder_service.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../projects/domain/models/project.dart';
import '../../../projects/domain/models/project_type.dart';
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
  String? _startupError;
  String _activeWebTab = 'html';

  // ── Split-view ────────────────────────────────────────────────────────────
  final ValueNotifier<double> _splitRatio =
      ValueNotifier<double>(_kDefaultSplitRatio);
  double _dragStartRatio = _kDefaultSplitRatio;
  double _dragStartDy    = 0.0;

  // ── Execution engine ──────────────────────────────────────────────────────
  final PythonRunnerService _pythonRunner = PythonRunnerService();
  final ValueNotifier<OutputPaneState> _outputState =
      ValueNotifier<OutputPaneState>(const OutputPaneState());



  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    debugPrint("APP_START: WorkspacePage initState");
    _controller.addListener(_onTextChanged);
    _initializeStartupFlow();
  }

  Future<void> _initializeStartupFlow() async {
    try {
      debugPrint("APP_START: before database open");
      // Prime the database connection
      await DatabaseHelper.instance.database.timeout(const Duration(seconds: 10));
      debugPrint("APP_START: after database open");
      
      debugPrint("APP_START: before session recovery");
      await _loadSession().timeout(const Duration(seconds: 10));
      debugPrint("APP_START: after session recovery");
    } catch (e, st) {
      debugPrint("APP_START: startup failed! $e");
      debugPrint(st.toString());
      if (mounted) {
        setState(() {
          _startupError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSession() async {
    
    final lastProjId = await _sessionManager.getLastProjectId();
    Project? p;
    if (lastProjId != null) {
      
      p = await _projectRepo.getProject(lastProjId);
    }
    
    p ??= await _projectRepo.createProject(
      title: 'My First Python Project',
      projectType: ProjectType.python,
      pythonContent: _kWelcomeSnippet,
    );

    _activeWebTab = await _sessionManager.getLastWebTab();
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
    
    if (project.projectType == ProjectType.web) {
      if (_activeWebTab == 'html') {
        _controller.text = project.htmlContent;
      } else if (_activeWebTab == 'css') {
        _controller.text = project.cssContent;
      } else {
        _controller.text = project.jsContent;
      }
    } else {
      _controller.text = project.pythonContent;
    }

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
    Project updated;
    
    if (_activeProject!.projectType == ProjectType.web) {
      if (_activeWebTab == 'html' && _activeProject!.htmlContent == newCode) return;
      if (_activeWebTab == 'css' && _activeProject!.cssContent == newCode) return;
      if (_activeWebTab == 'js' && _activeProject!.jsContent == newCode) return;

      updated = _activeProject!.copyWith(
        htmlContent: _activeWebTab == 'html' ? newCode : null,
        cssContent: _activeWebTab == 'css' ? newCode : null,
        jsContent: _activeWebTab == 'js' ? newCode : null,
        updatedAt: DatabaseHelper.nowMs(),
      );
    } else {
      if (_activeProject!.pythonContent == newCode) return; // No change
      updated = _activeProject!.copyWith(
        pythonContent: newCode,
        updatedAt: DatabaseHelper.nowMs(),
      );
    }

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

    // Save project and capture snapshot BEFORE execution
    await _saveCodeToDb();

    if (_activeProject != null) {
      String snapshotContent = '';
      if (_activeProject!.projectType == ProjectType.web) {
        snapshotContent = jsonEncode({
          'html': _activeProject!.htmlContent,
          'css': _activeProject!.cssContent,
          'js': _activeProject!.jsContent,
        });
      } else {
        snapshotContent = _activeProject!.pythonContent;
      }
      
      await _snapshotRepo.insertSnapshot(
        projectId: _activeProject!.id,
        codeContent: snapshotContent,
      );
    }

    if (_activeProject?.projectType == ProjectType.web) {
      final generatedHtml = WebProjectBuilderService().build(_activeProject!);
      
      _outputState.value = OutputPaneState(
        htmlSource: generatedHtml,
        activeTab:  OutputTab.preview,
        isRunning:  false,
      );
      return;
    }

    // Python mode.
    final code = _controller.text;
    if (code.trim().isEmpty) return;

    _outputState.value = _outputState.value.copyWith(
      isRunning: true,
      result:    null,
      activeTab: OutputTab.output,
    );

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
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00E5FF)),
              SizedBox(height: 16),
              Text('Loading workspace...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_startupError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                const SizedBox(height: 16),
                const Text('Startup Error', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text(_startupError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _startupError = null;
                    });
                    _initializeStartupFlow();
                  },
                  child: const Text('Retry'),
                )
              ],
            ),
          ),
        ),
      );
    }

    if (_activeProject == null) {
      return const Scaffold(backgroundColor: Color(0xFF0D1117));
    }

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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_activeProject?.projectType == ProjectType.web)
                                _buildWebTabs(),
                              Expanded(
                                child: CodeEditor(
                                  controller: _controller,
                                  focusNode:  _focusNode,
                                ),
                              ),
                            ],
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
  Future<bool> _confirmDeleteProject(Project p) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2D35),
          title: const Text('Delete Project', style: TextStyle(color: Colors.white)),
          content: Text('Are you sure you want to delete "${p.title}"? This cannot be undone.', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _renameProject(Project p, List<Project> projects, StateSetter setSheetState) async {
    final controller = TextEditingController(text: p.title);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2D35),
          title: const Text('Rename Project', style: TextStyle(color: Colors.white)),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Project Name',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Name cannot be empty';
                final name = val.trim();
                if (name == p.title) return null; // No change
                if (projects.any((proj) => proj.title.toLowerCase() == name.toLowerCase())) {
                  return 'A project with this name already exists';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('Rename', style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ],
        );
      },
    );

    if (newName != null && newName != p.title) {
      final updatedProject = p.copyWith(title: newName);
      await _projectRepo.updateProject(updatedProject);
      if (_activeProject?.id == p.id) {
        setState(() {
          _activeProject = updatedProject;
        });
      }
      setSheetState(() {
        projects[projects.indexWhere((proj) => proj.id == p.id)] = updatedProject;
      });
    }
  }

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
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                        color: const Color(0xFF2A2D35),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'new',
                            child: Text('New Project', style: TextStyle(color: Colors.white)),
                          ),
                          const PopupMenuItem(
                            value: 'import_py',
                            child: Text('Import Python File', style: TextStyle(color: Colors.white)),
                          ),
                          const PopupMenuItem(
                            value: 'import_web_zip',
                            child: Text('Import Web ZIP', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'new') {
                            final nav = Navigator.of(context);
                            await showDialog(
                              context: context,
                              builder: (context) => _CreateProjectDialog(
                                existingProjects: projects,
                                onProjectCreated: (p) {
                                  nav.pop(); // pop dialog
                                  nav.pop(); // pop bottom sheet
                                  _openProject(p);
                                },
                              ),
                            );
                          } else if (value == 'import_py') {
                            await _importPythonFile(projects);
                          } else if (value == 'import_web_zip') {
                            await _importWebZipFile(projects);
                          }
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.projectType == ProjectType.python ? "Python Project" : "Web Project",
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                            Text(
                              "Last opened: ${DateTime.fromMillisecondsSinceEpoch(p.lastOpenedAt).toString().split('.').first}",
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.grey),
                          color: const Color(0xFF2A2D35),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename', style: TextStyle(color: Colors.white)),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Text('Export', style: TextStyle(color: Colors.white)),
                            ),
                            if (projects.length > 1)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                              ),
                          ],
                          onSelected: (value) async {
                            final nav = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            
                            if (value == 'rename') {
                              await _renameProject(p, projects, setSheetState);
                            } else if (value == 'export') {
                              final path = await ProjectExportService().exportProjectAsZip(p);
                              if (path == null) return;
                              messenger.showSnackBar(
                                SnackBar(content: Text('Exported to: $path')),
                              );
                            } else if (value == 'delete') {
                               final confirm = await _confirmDeleteProject(p);
                               if (!confirm) return;
                               await _projectRepo.deleteProject(p.id);
                               if (isActive) {
                                 nav.pop();
                                 _loadSession(); // Load another project
                               } else {
                                 setSheetState(() {
                                   projects.removeAt(index);
                                 });
                               }
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

  Future<void> _importPythonFile(List<Project> projects) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['py'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        if (file.path == null || file.path!.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid file path.')),
            );
          }
          return;
        }

        if (!file.name.toLowerCase().endsWith('.py')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Only .py files are supported.')),
            );
          }
          return;
        }

        final path = file.path!;
        final fileObj = File(path);
        final content = await fileObj.readAsString();
        
        final filename = file.name;
        String defaultName = filename;
        if (defaultName.toLowerCase().endsWith('.py')) {
          defaultName = defaultName.substring(0, defaultName.length - 3);
        }

        if (mounted) {
          final nav = Navigator.of(context);
          await showDialog(
            context: context,
            builder: (context) => _CreateProjectDialog(
              existingProjects: projects,
              initialName: defaultName,
              importedPythonContent: content,
              onProjectCreated: (p) {
                nav.pop(); // pop dialog
                nav.pop(); // pop bottom sheet
                _openProject(p);
              },
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read file: $e')),
        );
      }
    }
  }

  Future<void> _importWebZipFile(List<Project> projects) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.single;

        if (pickedFile.path == null || pickedFile.path!.isEmpty) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid file path.')));
          return;
        }

        final bytes = await File(pickedFile.path!).readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        ArchiveFile? indexHtmlFile;
        String prefix = '';

        for (final file in archive) {
          if (file.isFile && file.name.endsWith('index.html')) {
            indexHtmlFile = file;
            prefix = file.name.substring(0, file.name.length - 'index.html'.length);
            break;
          }
        }

        if (indexHtmlFile == null) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No index.html found in the ZIP.')));
          return;
        }

        final String htmlContent = utf8.decode(indexHtmlFile.content as List<int>);
        String cssContent = '';
        String jsContent = '';

        for (final file in archive) {
          if (file.isFile) {
            if (file.name == '${prefix}style.css') {
              cssContent = utf8.decode(file.content as List<int>);
            } else if (file.name == '${prefix}script.js') {
              jsContent = utf8.decode(file.content as List<int>);
            }
          }
        }

        final filename = pickedFile.name;
        String defaultName = filename;
        if (defaultName.toLowerCase().endsWith('.zip')) {
          defaultName = defaultName.substring(0, defaultName.length - 4);
        }

        if (mounted) {
          final nav = Navigator.of(context);
          await showDialog(
            context: context,
            builder: (context) => _CreateProjectDialog(
              existingProjects: projects,
              initialName: defaultName,
              importedHtmlContent: htmlContent,
              importedCssContent: cssContent,
              importedJsContent: jsContent,
              onProjectCreated: (p) {
                nav.pop(); // pop dialog
                nav.pop(); // pop bottom sheet
                _openProject(p);
              },
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read ZIP file: $e')),
        );
      }
    }
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

  // ── Web Tabs ──────────────────────────────────────────────────────────────
  Widget _buildWebTabs() {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildTabButton('html', 'HTML'),
          const SizedBox(width: 8),
          _buildTabButton('css', 'CSS'),
          const SizedBox(width: 8),
          _buildTabButton('js', 'JS'),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabId, String label) {
    final isActive = _activeWebTab == tabId;
    return GestureDetector(
      onTap: () => _switchWebTab(tabId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00E5FF).withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? const Color(0xFF00E5FF) : const Color(0xFF30363D),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? const Color(0xFF00E5FF) : Colors.grey,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _switchWebTab(String newTab) async {
    if (_activeWebTab == newTab || _activeProject == null) return;
    
    // Unfocus and explicitly save the current tab before switching
    _focusNode.unfocus();
    await _saveCodeToDb();
    
    setState(() {
      _activeWebTab = newTab;
    });
    
    await _sessionManager.setLastWebTab(newTab);
    
    if (_activeProject!.projectType == ProjectType.web) {
      if (newTab == 'html') {
        _controller.text = _activeProject!.htmlContent;
      } else if (newTab == 'css') {
        _controller.text = _activeProject!.cssContent;
      } else {
        _controller.text = _activeProject!.jsContent;
      }
    }
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

// ─────────────────────────────────────────────────────────────────────────────
// Create Project Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _CreateProjectDialog extends StatefulWidget {
  final List<Project> existingProjects;
  final Function(Project) onProjectCreated;
  final String? initialName;
  final String? importedPythonContent;
  final String? importedHtmlContent;
  final String? importedCssContent;
  final String? importedJsContent;

  const _CreateProjectDialog({
    required this.existingProjects,
    required this.onProjectCreated,
    this.initialName,
    this.importedPythonContent,
    this.importedHtmlContent,
    this.importedCssContent,
    this.importedJsContent,
  });

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _nameController = TextEditingController();
  ProjectType _selectedType = ProjectType.python;
  String? _errorMessage;
  final ProjectRepository _projectRepo = ProjectRepository();

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
    if (widget.importedPythonContent != null) {
      _selectedType = ProjectType.python;
    } else if (widget.importedHtmlContent != null) {
      _selectedType = ProjectType.web;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Project name cannot be empty.');
      return;
    }

    final isDuplicate = widget.existingProjects.any((p) => p.title.toLowerCase() == name.toLowerCase());
    if (isDuplicate) {
      setState(() => _errorMessage = 'A project with this name already exists.');
      return;
    }

    setState(() => _errorMessage = null);

    Project newProject;
    if (_selectedType == ProjectType.python) {
      newProject = await _projectRepo.createProject(
        title: name,
        projectType: ProjectType.python,
        pythonContent: widget.importedPythonContent ?? 'print("Hello, World!")',
      );
    } else {
      newProject = await _projectRepo.createProject(
        title: name,
        projectType: ProjectType.web,
        htmlContent: widget.importedHtmlContent ?? '<!DOCTYPE html>\n<html>\n<head>\n  <title>My Web Project</title>\n</head>\n<body>\n  <h1>Hello World</h1>\n  <p>Edit the HTML, CSS, and JavaScript tabs, then press Run.</p>\n</body>\n</html>',
        cssContent: widget.importedCssContent ?? 'body {\n  font-family: sans-serif;\n  padding: 20px;\n}',
        jsContent: widget.importedJsContent ?? 'console.log("Hello from JavaScript!");',
      );
    }

    widget.onProjectCreated(newProject);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2329),
      title: const Text('New Project', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Project Name',
              labelStyle: const TextStyle(color: Colors.grey),
              errorText: _errorMessage,
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
            ),
          ),
          if (widget.importedPythonContent == null && widget.importedHtmlContent == null) ...[
            const SizedBox(height: 24),
            const Text('Project Type', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            SegmentedButton<ProjectType>(
              segments: const [
                ButtonSegment<ProjectType>(
                  value: ProjectType.python,
                  label: Text('Python'),
                  icon: Icon(Icons.code),
                ),
                ButtonSegment<ProjectType>(
                  value: ProjectType.web,
                  label: Text('Web'),
                  icon: Icon(Icons.language),
                ),
              ],
              selected: <ProjectType>{_selectedType},
              onSelectionChanged: (Set<ProjectType> newSelection) {
                setState(() {
                  _selectedType = newSelection.first;
                });
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: const Color(0xFF00E5FF).withAlpha(40),
                selectedForegroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.grey,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: _handleCreate,
          child: const Text('Create', style: TextStyle(color: Color(0xFF00E5FF))),
        ),
      ],
    );
  }
}
