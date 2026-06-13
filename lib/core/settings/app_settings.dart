import 'package:flutter/material.dart';

class AppSettings {
  final ThemeMode themeMode;
  final double editorFontSize;
  final double outputFontSize;
  final int tabSize;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.editorFontSize = 16.0,
    this.outputFontSize = 14.0,
    this.tabSize = 4,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? editorFontSize,
    double? outputFontSize,
    int? tabSize,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      outputFontSize: outputFontSize ?? this.outputFontSize,
      tabSize: tabSize ?? this.tabSize,
    );
  }
}
