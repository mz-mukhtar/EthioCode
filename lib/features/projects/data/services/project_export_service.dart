import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ethiocode/features/projects/domain/models/project.dart';
import 'package:ethiocode/features/projects/domain/models/project_type.dart';

class ProjectExportService {
  Future<String?> exportProjectAsZip(Project project) async {
    final archive = Archive();

    if (project.projectType == ProjectType.python) {
      final content = utf8.encode(project.pythonContent);
      archive.addFile(ArchiveFile('main.py', content.length, content));
    } else if (project.projectType == ProjectType.web) {
      final html = utf8.encode(project.htmlContent);
      archive.addFile(ArchiveFile('index.html', html.length, html));
      final css = utf8.encode(project.cssContent);
      archive.addFile(ArchiveFile('style.css', css.length, css));
      final js = utf8.encode(project.jsContent);
      archive.addFile(ArchiveFile('script.js', js.length, js));
    }

    final zipData = ZipEncoder().encode(archive);

    final bytes = Uint8List.fromList(zipData);

    final String? result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Project',
      fileName: '${project.title}.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: bytes,
    );

    return result;
  }
}
