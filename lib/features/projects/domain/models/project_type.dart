// lib/features/projects/domain/models/project_type.dart

enum ProjectType {
  python,
  web,
}

extension ProjectTypeExtension on ProjectType {
  String get name {
    switch (this) {
      case ProjectType.python:
        return 'python';
      case ProjectType.web:
        return 'web';
    }
  }

  static ProjectType fromString(String val) {
    switch (val) {
      case 'web':
        return ProjectType.web;
      case 'python':
      default:
        return ProjectType.python;
    }
  }
}
