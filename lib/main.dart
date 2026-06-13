import "dart:io" show Platform;
import 'package:flutter/material.dart';
import 'features/workspace/presentation/pages/workspace_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/settings/settings_service.dart';
import 'core/settings/settings_controller.dart';

// Global settings controller accessible throughout the app
late final SettingsController globalSettingsController;

void main() async {
  
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  globalSettingsController = SettingsController(SettingsService());
  await globalSettingsController.loadSettings();
  
  runApp(const EthioCodeApp());
}

class EthioCodeApp extends StatelessWidget {
  const EthioCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: globalSettingsController,
      builder: (context, _) {
        return MaterialApp(
          title: 'EthioCode',
          debugShowCheckedModeBanner: false,
          themeMode: globalSettingsController.settings.themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00E5FF),
              brightness: Brightness.light,
            ),
            fontFamily: 'monospace',
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00E5FF),
              brightness: Brightness.dark,
              surface: const Color(0xFF0D1117),
            ),
            scaffoldBackgroundColor: const Color(0xFF0D1117),
            fontFamily: 'monospace',
            useMaterial3: true,
          ),
          home: const WorkspacePage(),
        );
      },
    );
  }
}
