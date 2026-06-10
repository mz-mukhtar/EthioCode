import 'package:flutter/material.dart';
import 'features/workspace/presentation/pages/workspace_page.dart';

void main() {
  runApp(const EthioCodeApp());
}

class EthioCodeApp extends StatelessWidget {
  const EthioCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EthioCode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
  }
}
