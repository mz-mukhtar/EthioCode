// lib/features/workspace/domain/services/web_project_builder_service.dart

import '../../../projects/domain/models/project.dart';

class WebProjectBuilderService {
  /// Combines the HTML, CSS, and JS from a [Project] into a single HTML string
  /// suitable for rendering in a WebView.
  String build(Project project) {
    String html = project.htmlContent;
    final css = project.cssContent.trim();
    final js = project.jsContent.trim();

    const String basePreviewCss = '''
html, body {
  background: #ffffff;
  color: #111111;
  margin: 0;
  min-height: 100%;
}
body {
  padding: 20px;
  box-sizing: border-box;
}
''';

    // 1. Safe Fragment Handling
    final htmlLower = html.toLowerCase();
    if (!htmlLower.contains('<html') && !htmlLower.contains('<body')) {
      html = '''<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body>
$html
</body>
</html>''';
    }

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

    // 3. Inject Base CSS
    const baseStyleBlock = '\n<style id="mobile-ide-preview-base-style">\n$basePreviewCss\n</style>\n';
    if (html.contains('</head>')) {
      html = html.replaceFirst('</head>', '$baseStyleBlock</head>');
    } else if (html.contains('<body>')) {
      html = html.replaceFirst('<body>', '<body>$baseStyleBlock');
    } else {
      html = baseStyleBlock + html;
    }

    // 4. Inject User CSS
    if (css.isNotEmpty) {
      final styleBlock = '\n<style id="mobile-ide-user-style">\n$css\n</style>\n';
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
