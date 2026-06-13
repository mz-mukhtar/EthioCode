import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'settings_service.dart';

class SettingsController with ChangeNotifier {
  SettingsController(this._settingsService);

  final SettingsService _settingsService;

  late AppSettings _settings;
  AppSettings get settings => _settings;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> loadSettings() async {
    _settings = await _settingsService.loadSettings();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode? newThemeMode) async {
    if (newThemeMode == null || newThemeMode == _settings.themeMode) return;
    _settings = _settings.copyWith(themeMode: newThemeMode);
    notifyListeners();
    await _settingsService.saveSettings(_settings);
  }

  Future<void> updateEditorFontSize(double? newSize) async {
    if (newSize == null || newSize == _settings.editorFontSize) return;
    _settings = _settings.copyWith(editorFontSize: newSize);
    notifyListeners();
    await _settingsService.saveSettings(_settings);
  }

  Future<void> updateOutputFontSize(double? newSize) async {
    if (newSize == null || newSize == _settings.outputFontSize) return;
    _settings = _settings.copyWith(outputFontSize: newSize);
    notifyListeners();
    await _settingsService.saveSettings(_settings);
  }

  Future<void> updateTabSize(int? newSize) async {
    if (newSize == null || newSize == _settings.tabSize) return;
    _settings = _settings.copyWith(tabSize: newSize);
    notifyListeners();
    await _settingsService.saveSettings(_settings);
  }
}
