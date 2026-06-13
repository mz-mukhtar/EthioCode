import 'package:flutter/material.dart';
import '../../../../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: globalSettingsController,
      builder: (context, _) {
        final settings = globalSettingsController.settings;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings', style: TextStyle(fontFamily: 'monospace')),
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? const Color(0xFF161B22),
            foregroundColor: Colors.white,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            children: [
              _buildSectionHeader('Appearance'),
              ListTile(
                title: const Text('Theme', style: TextStyle(fontFamily: 'monospace')),
                subtitle: const Text('System / Light / Dark', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                trailing: DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  underline: const SizedBox(),
                  style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).textTheme.bodyLarge?.color),
                  items: const [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                  ],
                  onChanged: (mode) => globalSettingsController.updateThemeMode(mode),
                ),
              ),
              const Divider(),
              _buildSectionHeader('Editor'),
              ListTile(
                title: const Text('Editor Font Size', style: TextStyle(fontFamily: 'monospace')),
                trailing: DropdownButton<double>(
                  value: settings.editorFontSize,
                  underline: const SizedBox(),
                  style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).textTheme.bodyLarge?.color),
                  items: [12.0, 14.0, 16.0, 18.0, 20.0, 22.0].map((size) {
                    return DropdownMenuItem(value: size, child: Text(size.toInt().toString()));
                  }).toList(),
                  onChanged: (size) => globalSettingsController.updateEditorFontSize(size),
                ),
              ),
              ListTile(
                title: const Text('Tab Size', style: TextStyle(fontFamily: 'monospace')),
                subtitle: const Text('Number of spaces for indentation', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                trailing: DropdownButton<int>(
                  value: settings.tabSize,
                  underline: const SizedBox(),
                  style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).textTheme.bodyLarge?.color),
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 spaces')),
                    DropdownMenuItem(value: 4, child: Text('4 spaces')),
                  ],
                  onChanged: (size) => globalSettingsController.updateTabSize(size),
                ),
              ),
              const Divider(),
              _buildSectionHeader('Output'),
              ListTile(
                title: const Text('Output Font Size', style: TextStyle(fontFamily: 'monospace')),
                subtitle: const Text('Size of console and error output text', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                trailing: DropdownButton<double>(
                  value: settings.outputFontSize,
                  underline: const SizedBox(),
                  style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).textTheme.bodyLarge?.color),
                  items: [12.0, 14.0, 16.0, 18.0, 20.0].map((size) {
                    return DropdownMenuItem(value: size, child: Text(size.toInt().toString()));
                  }).toList(),
                  onChanged: (size) => globalSettingsController.updateOutputFontSize(size),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
