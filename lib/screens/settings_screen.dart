import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/database_provider.dart';
import '../utils/backup_restore.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _handleExport(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final result = await exportBackup(db);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _handleRestore(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This will replace ALL current data with the contents of the backup file. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final db = ref.read(databaseProvider);
    final result = await restoreBackup(db);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Appearance',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (value) =>
            ref.read(themeModeProvider.notifier).state = value!,
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('System default'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dark'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
          const Divider(height: 32),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Backup & Restore',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export backup'),
            subtitle: const Text('Save all projects and transactions to a file'),
            onTap: () => _handleExport(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Restore backup'),
            subtitle: const Text('Replace current data from a backup file'),
            onTap: () => _handleRestore(context, ref),
          ),
        ],
      ),
    );
  }
}