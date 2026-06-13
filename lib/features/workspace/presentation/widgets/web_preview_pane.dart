// lib/features/workspace/presentation/widgets/web_preview_pane.dart
//
// A self-contained widget that renders an offline HTML/CSS/JS preview using
// the webview_flutter package.
//
// Design goals:
//   • Zero internet dependency – all content is loaded via a data URI so the
//     app works fully offline on every device.
//   • Isolated reload – only the WebView content is refreshed when the HTML
//     source changes; the rest of the UI tree is unaffected.
//   • Lifecycle safety – the WebViewController is created lazily and disposed
//     correctly via a dedicated State class.
//   • JavaScript explicitly enabled (JavaScriptMode.unrestricted).
//   • Navigation lock – all anchor clicks and form submissions that would
//     trigger a real network request are blocked by a NavigationDelegate.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const Color _kPaneBg    = Color(0xFFFFFFFF); // Light background for preview
const Color _kEmptyFg   = Color(0xFF484F58); // Darker grey for light bg readability
const Color _kActiveFg  = Color(0xFF00E5FF);

// ─────────────────────────────────────────────────────────────────────────────
// WebPreviewPane
// ─────────────────────────────────────────────────────────────────────────────

/// Renders [htmlSource] in an offline WebView.
///
/// Pass an empty string (or null) to show the idle placeholder.
/// Call [WebPreviewPaneController.reload] from a parent to force a reload
/// without pushing a new widget into the tree.
class WebPreviewPane extends StatefulWidget {
  /// Raw HTML source to render. Passing an empty string shows a placeholder.
  final String htmlSource;

  /// Optional controller so the parent widget can trigger reloads.
  final WebPreviewPaneController? controller;

  /// Callback for JavaScript console messages.
  final void Function(String message, bool isError)? onConsoleMessage;

  const WebPreviewPane({
    super.key,
    required this.htmlSource,
    this.controller,
    this.onConsoleMessage,
  });

  @override
  State<WebPreviewPane> createState() => _WebPreviewPaneState();
}

class _WebPreviewPaneState extends State<WebPreviewPane> {
  // ── WebViewController ─────────────────────────────────────────────────────
  late final WebViewController _webController;
  bool _isLoading = false;
  String? _navigationError;

  // ── State tracking ────────────────────────────────────────────────────────
  /// The last HTML source that was actually loaded into the WebView.
  String _loadedSource = '';

  @override
  void initState() {
    super.initState();
    _initWebController();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(WebPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detach old controller, attach new one.
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }

    // Auto-reload if the HTML source changed.
    if (widget.htmlSource != oldWidget.htmlSource) {
      _loadHtml(widget.htmlSource);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  // ── WebView initialisation ─────────────────────────────────────────────────
  void _initWebController() {
    _webController = WebViewController()
      // ── JavaScript: unrestricted (required for student JS exercises) ──────
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // ── Console Output Channel ─────────────────────────────────────────────
      ..addJavaScriptChannel(
        'EthioCodeConsole',
        onMessageReceived: (JavaScriptMessage message) {
          final text = message.message;
          final isError = text.startsWith('ERROR: ');
          final msg = text.replaceFirst(RegExp(r'^(LOG|ERROR):\s*'), '');
          widget.onConsoleMessage?.call(msg, isError);
        },
      )
      // ── Background colour matches the default white theme ─────────────────
      ..setBackgroundColor(_kPaneBg)
      // ── Navigation delegate: block all non-data-URI navigations ──────────
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            // Ignore errors on blank / initial load.
            if (error.errorCode == -1) return;
            debugPrint('WebView error ${error.errorCode}: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _navigationError = 'Failed to load web preview.';
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Only allow data URIs – block all external navigation attempts.
            final uri = request.url;
            if (uri.startsWith('data:') || uri == 'about:blank') {
              return NavigationDecision.navigate;
            }
            // Silently block any attempt to navigate to a real URL.
            return NavigationDecision.prevent;
          },
        ),
      );

    // Load the initial HTML if one was provided.
    if (widget.htmlSource.isNotEmpty) {
      _loadHtml(widget.htmlSource);
    }
  }

  // ── HTML loading ──────────────────────────────────────────────────────────

  /// Encode [html] as a data URI and load it into the WebView.
  ///
  /// Using [loadRequest] with a data URI is preferred over [loadHtmlString]
  /// because it correctly sets the MIME type and charset, preventing encoding
  /// issues with Unicode characters (e.g. Amharic script in output).
  void _loadHtml(String html) {
    if (html == _loadedSource) return; // idempotent – skip redundant reloads.
    _loadedSource = html;
    _navigationError = null;

    final uri = Uri.dataFromString(
      html,
      mimeType:  'text/html',
      encoding:  Uri.encodeComponent('').runes.isNotEmpty
          ? null
          : null, // let Dart use UTF-8 by default
    );

    _webController.loadRequest(uri);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPaneBg,
      child: Stack(
        children: [
          // ── WebView (always present; hidden behind placeholder when empty) ──
          if (widget.htmlSource.isNotEmpty)
            WebViewWidget(controller: _webController),

          // ── Empty-state placeholder ──────────────────────────────────────
          if (widget.htmlSource.isEmpty) _buildPlaceholder(),

          // ── Loading overlay ───────────────────────────────────────────────
          if (_isLoading) _buildLoadingOverlay(),

          // ── Error overlay ─────────────────────────────────────────────────
          if (_navigationError != null) _buildErrorOverlay(_navigationError!),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.web_outlined,
            size:  36,
            color: _kEmptyFg.withAlpha(140),
          ),
          const SizedBox(height: 10),
          const Text(
            'Run your web project to see the preview.',
            style: TextStyle(
              fontFamily:    'monospace',
              fontSize:      12.0,
              color:         _kEmptyFg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return const Positioned.fill(
      child: ColoredBox(
        color: Color(0x33FFFFFF), // lighter overlay

        child: Center(
          child: SizedBox(
            width:  24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color:       _kActiveFg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(String message) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color:   const Color(0xFFFFEBEB), // Light red bg for visibility
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Text(
          message,
          maxLines:  3,
          overflow:  TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize:   12.0,
            color:      Color(0xFFD32F2F), // Dark red text
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WebPreviewPaneController
// ─────────────────────────────────────────────────────────────────────────────

/// An imperative controller that allows a parent widget (e.g. [WorkspacePage])
/// to trigger isolated WebView operations without rebuilding the whole tree.
///
/// ```dart
/// final _previewController = WebPreviewPaneController();
///
/// // Reload from the parent:
/// _previewController.reload(newHtmlSource);
/// ```
class WebPreviewPaneController extends ChangeNotifier {
  _WebPreviewPaneState? _state;

  void _attach(_WebPreviewPaneState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Force-reload the WebView with [html].  If [html] is the same string as
  /// the currently loaded content the call is a no-op (idempotent).
  void reload(String html) {
    _state?._loadHtml(html);
  }

  /// Clear the WebView and show the idle placeholder.
  void clear() {
    _state?._webController.loadRequest(Uri.parse('about:blank'));
    _state?._loadedSource = '';
  }

  @override
  void dispose() {
    _state = null;
    super.dispose();
  }
}
