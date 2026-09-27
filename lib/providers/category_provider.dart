import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../database/database.dart';
import 'database_provider.dart';

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.categories).watch();
});

Future<void> seedDefaultCategoriesIfNeeded(AppDatabase db) async {
  final existing = await db.select(db.categories).get();
  if (existing.isNotEmpty) return;

  const defaultExpenseCategories = [
    'Labor',
    'Fuel',
    'Cement',
    'Sand',
    'Steel',
    'Transportation',
    'Food',
    'Equipment',
    'Maintenance',
    'Other',
  ];

  const defaultIncomeCategories = [
    'Client Payment',
    'Advance',
    'Other Income',
  ];

  for (final name in defaultExpenseCategories) {
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        type: 'expense',
        isCustom: const Value(false),
      ),
    );
  }

  for (final name in defaultIncomeCategories) {
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        type: 'income',
        isCustom: const Value(false),
      ),
    );
  }
}