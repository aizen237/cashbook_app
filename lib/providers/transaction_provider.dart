import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../database/database.dart';
import 'database_provider.dart';

final transactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.transactions)
    ..orderBy([(t) => OrderingTerm.desc(t.date)]))
      .watch();
});

class TransactionInput {
  final double amount;
  final String type; // 'income' or 'expense'
  final int projectId;
  final String? description;
  final DateTime date;
  final String? paymentMethod;
  final String? receiptImagePath;

  TransactionInput({
    required this.amount,
    required this.type,
    required this.projectId,
    this.description,
    required this.date,
    this.paymentMethod,
    this.receiptImagePath,
  });
}

final transactionActionsProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return TransactionActions(db);
});

class TransactionActions {
  final AppDatabase db;
  TransactionActions(this.db);

  Future<void> addTransaction(TransactionInput input) async {
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        amount: input.amount,
        type: input.type,
        projectId: input.projectId,
        description: Value(input.description),
        date: Value(input.date),
        paymentMethod: Value(input.paymentMethod),
        receiptImagePath: Value(input.receiptImagePath),
      ),
    );
  }

  Future<void> updateTransaction(int id, TransactionInput input) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        amount: Value(input.amount),
        type: Value(input.type),
        projectId: Value(input.projectId),
        description: Value(input.description),
        date: Value(input.date),
        paymentMethod: Value(input.paymentMethod),
        receiptImagePath: Value(input.receiptImagePath),
      ),
    );
  }

  Future<void> deleteTransaction(int id) async {
    await (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
  }
}

final projectTransactionsProvider =
StreamProvider.family<List<Transaction>, int>((ref, projectId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.transactions)
    ..where((t) => t.projectId.equals(projectId))
    ..orderBy([(t) => OrderingTerm.desc(t.date)]);
  return query.watch();
});