import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/database_provider.dart';
import '../providers/security_provider.dart';
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

  Future<void> _showSetPinDialog(
      BuildContext context, WidgetRef ref, {bool isChanging = false}) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? errorMessage;

    final success = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(isChanging ? 'Change PIN' : 'Set 4-Digit PIN'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Enter 4-digit PIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final pin = controller.text.trim();
                    final confirm = confirmController.text.trim();

                    if (pin.length != 4 || int.tryParse(pin) == null) {
                      setState(() {
                        errorMessage = 'PIN must be 4 digits';
                      });
                      return;
                    }

                    if (pin != confirm) {
                      setState(() {
                        errorMessage = 'PINs do not match';
                      });
                      return;
                    }

                    ref.read(securityProvider.notifier).setPin(pin);
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (success == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isChanging
              ? 'PIN updated successfully'
              : 'PIN protection enabled'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final security = ref.watch(securityProvider);

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
            child: Text('App Security',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('PIN Protection'),
            subtitle: Text(security.isPinEnabled
                ? 'App is protected with a 4-digit PIN'
                : 'Require PIN to open the app'),
            value: security.isPinEnabled,
            onChanged: (enabled) {
              if (enabled) {
                _showSetPinDialog(context, ref);
              } else {
                ref.read(securityProvider.notifier).disablePin();
              }
            },
          ),
          if (security.isPinEnabled) ...[
            ListTile(
              leading: const SizedBox.shrink(),
              title: const Text('Change PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showSetPinDialog(context, ref, isChanging: true),
            ),
            if (security.isBiometricSupported)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Biometric Unlock'),
                subtitle: const Text('Unlock using Fingerprint or Face ID'),
                value: security.isBiometricEnabled,
                onChanged: (enabled) {
                  ref
                      .read(securityProvider.notifier)
                      .setBiometricEnabled(enabled);
                },
              ),
          ],
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