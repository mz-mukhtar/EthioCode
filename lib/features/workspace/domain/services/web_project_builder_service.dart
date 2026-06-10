// lib/features/workspace/domain/services/web_project_builder_service.dart

import '../../../projects/domain/models/project.dart';

class WebProjectBuilderService {
  /// Combines the HTML, CSS, and JS from a [Project] into a single HTML string
  /// suitable for rendering in a WebView.
  String build(Project project) {
    String html = project.htmlContent;
    final css = project.cssContent.trim();
    final js = project.jsContent.trim();

    const consoleOverride = '''
<script>
(function() {
  var originalLog = console.log;
  var originalError = console.error;

  function postMsg(type, args) {
    try {
      var msg = Array.from(args).map(function(a) {
        if (typeof a === "object") {
          try { return JSON.stringify(a); } catch(e) { return String(a); }
        }
        return String(a);
      }).join(" ");
      if (window.EthioCodeConsole) {
        window.EthioCodeConsole.postMessage(type + ": " + msg);
      }
    } catch(e) {}
  }

  console.log = function() {
    postMsg("LOG", arguments);
    originalLog.apply(console, arguments);
  };

  console.error = function() {
    postMsg("ERROR", arguments);
    originalError.apply(console, arguments);
  };
})();
</script>
''';

    if (html.contains('<head>')) {
      html = html.replaceFirst('<head>', '<head>\\n$consoleOverride');
    } else if (html.contains('<html>')) {
      html = html.replaceFirst('<html>', '<html>\\n$consoleOverride');
    } else {
      html = consoleOverride + html;
    }

    if (css.isNotEmpty) {
      final styleBlock = '\n<style>\n$css\n</style>\n';
      if (html.contains('</head>')) {
        html = html.replaceFirst('</head>', '$styleBlock</head>');
      } else {
        html += styleBlock;
      }
    }

    if (js.isNotEmpty) {
      final scriptBlock = '\n<script>\n$js\n</script>\n';
      if (html.contains('</body>')) {
        html = html.replaceFirst('</body>', '$scriptBlock</body>');
      } else {
        html += scriptBlock;
      }
    }

    return html;
  }
}
