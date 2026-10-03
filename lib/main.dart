import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/security_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_shell.dart';
import 'screens/lock_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CashbookApp(),
    ),
  );
}

class CashbookApp extends ConsumerWidget {
  const CashbookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final security = ref.watch(securityProvider);

    Widget homeWidget;
    if (security.isPinEnabled && !security.isAuthenticated) {
      homeWidget = const LockScreen();
    } else {
      homeWidget = const HomeShell();
    }

    return MaterialApp(
      title: 'Cashbook',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: homeWidget,
    );
  }
}