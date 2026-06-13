import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';

class SettingsService {
  static const _keyThemeMode = 'settings.themeMode';
  static const _keyEditorFontSize = 'settings.editorFontSize';
  static const _keyOutputFontSize = 'settings.outputFontSize';
  static const _keyTabSize = 'settings.tabSize';

  Future<AppSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final themeStr = prefs.getString(_keyThemeMode);
      ThemeMode themeMode = ThemeMode.system;
      if (themeStr == 'light') themeMode = ThemeMode.light;
      if (themeStr == 'dark') themeMode = ThemeMode.dark;

      final editorFontSize = prefs.getDouble(_keyEditorFontSize) ?? 16.0;
      final outputFontSize = prefs.getDouble(_keyOutputFontSize) ?? 14.0;
      final tabSize = prefs.getInt(_keyTabSize) ?? 4;

      return AppSettings(
        themeMode: themeMode,
        editorFontSize: editorFontSize,
        outputFontSize: outputFontSize,
        tabSize: tabSize,
      );
    } catch (e) {
      debugPrint('Failed to load settings: $e');
      return const AppSettings(); // defaults
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      String themeStr = 'system';
      if (settings.themeMode == ThemeMode.light) themeStr = 'light';
      if (settings.themeMode == ThemeMode.dark) themeStr = 'dark';
      
      await prefs.setString(_keyThemeMode, themeStr);
      await prefs.setDouble(_keyEditorFontSize, settings.editorFontSize);
      await prefs.setDouble(_keyOutputFontSize, settings.outputFontSize);
      await prefs.setInt(_keyTabSize, settings.tabSize);
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }
}
