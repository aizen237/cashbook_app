import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/database_provider.dart';
import 'providers/category_provider.dart';
import 'screens/home_shell.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  final db = container.read(databaseProvider);
  await seedDefaultCategoriesIfNeeded(db);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CashbookApp(),
    ),
  );
}

class CashbookApp extends StatelessWidget {
  const CashbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cashbook',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}