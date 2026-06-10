import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontFamily: 'monospace'),
        ),
        backgroundColor: const Color(0xFF161B22),
      ),
      body: const Center(
        child: Text(
          'Settings coming soon...',
          style: TextStyle(fontFamily: 'monospace', color: Colors.grey),
        ),
      ),
    );
  }
}
