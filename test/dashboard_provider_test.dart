import 'package:cashbook_app/database/database.dart';
import 'package:cashbook_app/providers/dashboard_provider.dart';
import 'package:cashbook_app/providers/database_provider.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('calculateDashboardData deterministic date boundary tests', () {
    final fixedNow = DateTime(2026, 10, 11, 14, 30); // Sun Oct 11 2026, 14:30

    test('1. Separates income and expense correctly for today', () {
      final txs = [
        Transaction(
          id: 1,
          amount: 500.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 10, 11, 09, 0),
        ),
        Transaction(
          id: 2,
          amount: 150.0,
          type: 'expense',
          projectId: 1,
          date: DateTime(2026, 10, 11, 11, 0),
        ),
      ];

      final result = calculateDashboardData(txs, fixedNow);

      expect(result.todayIncome, equals(500.0));
      expect(result.todayExpense, equals(150.0));
      expect(result.monthIncome, equals(500.0));
      expect(result.monthExpense, equals(150.0));
      expect(result.totalBalance, equals(350.0));
    });

    test('2. Handles yesterday transactions (included in month, excluded from today)', () {
      final txs = [
        Transaction(
          id: 1,
          amount: 1000.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 10, 10, 20, 0), // Yesterday
        ),
        Transaction(
          id: 2,
          amount: 200.0,
          type: 'expense',
          projectId: 1,
          date: DateTime(2026, 10, 11, 10, 0), // Today
        ),
      ];

      final result = calculateDashboardData(txs, fixedNow);

      expect(result.todayIncome, equals(0.0));
      expect(result.todayExpense, equals(200.0));
      expect(result.monthIncome, equals(1000.0));
      expect(result.monthExpense, equals(200.0));
      expect(result.totalBalance, equals(800.0));
    });

    test('3. Excludes tomorrow and future-dated transactions from today and this month', () {
      final txs = [
        Transaction(
          id: 1,
          amount: 500.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 10, 12, 09, 0), // Tomorrow
        ),
        Transaction(
          id: 2,
          amount: 300.0,
          type: 'expense',
          projectId: 1,
          date: DateTime(2026, 10, 20, 15, 0), // Later this month
        ),
        Transaction(
          id: 3,
          amount: 100.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 10, 11, 10, 0), // Today
        ),
      ];

      final result = calculateDashboardData(txs, fixedNow);

      expect(result.todayIncome, equals(100.0));
      expect(result.todayExpense, equals(0.0));
      expect(result.monthIncome, equals(100.0));
      expect(result.monthExpense, equals(0.0));
      // Total balance preserves all transactions (100 + 500 - 300 = 300)
      expect(result.totalBalance, equals(300.0));
    });

    test('4. Excludes transactions from future months and years from current month totals', () {
      final txs = [
        Transaction(
          id: 1,
          amount: 2000.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 11, 1, 10, 0), // Next month
        ),
        Transaction(
          id: 2,
          amount: 5000.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2027, 1, 15, 10, 0), // Next year
        ),
        Transaction(
          id: 3,
          amount: 400.0,
          type: 'expense',
          projectId: 1,
          date: DateTime(2026, 10, 5, 12, 0), // Earlier this month
        ),
      ];

      final result = calculateDashboardData(txs, fixedNow);

      expect(result.todayIncome, equals(0.0));
      expect(result.todayExpense, equals(0.0));
      expect(result.monthIncome, equals(0.0));
      expect(result.monthExpense, equals(400.0));
      expect(result.totalBalance, equals(6600.0));
    });

    test('5. Excludes transactions from previous months from current month totals', () {
      final txs = [
        Transaction(
          id: 1,
          amount: 3000.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 9, 30, 23, 59), // Last month
        ),
        Transaction(
          id: 2,
          amount: 1500.0,
          type: 'expense',
          projectId: 1,
          date: DateTime(2025, 10, 11, 10, 0), // Last year
        ),
        Transaction(
          id: 3,
          amount: 200.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 10, 11, 08, 0), // Today
        ),
      ];

      final result = calculateDashboardData(txs, fixedNow);

      expect(result.todayIncome, equals(200.0));
      expect(result.todayExpense, equals(0.0));
      expect(result.monthIncome, equals(200.0));
      expect(result.monthExpense, equals(0.0));
      expect(result.totalBalance, equals(1700.0));
    });

    test('6. Handles midnight boundaries correctly', () {
      final midnightStart = DateTime(2026, 10, 11, 0, 0, 0); // 00:00:00
      final justBeforeMidnight = DateTime(2026, 10, 10, 23, 59, 59, 999);

      final txs = [
        Transaction(
          id: 1,
          amount: 50.0,
          type: 'expense',
          projectId: 1,
          date: justBeforeMidnight,
        ),
        Transaction(
          id: 2,
          amount: 100.0,
          type: 'income',
          projectId: 1,
          date: midnightStart,
        ),
      ];

      final result = calculateDashboardData(txs, fixedNow);

      expect(result.todayIncome, equals(100.0));
      expect(result.todayExpense, equals(0.0));
      expect(result.monthIncome, equals(100.0));
      expect(result.monthExpense, equals(50.0));
    });

    test('7. Handles month and year transitions (Dec 31 to Jan 1)', () {
      final newYearsDayNow = DateTime(2027, 1, 1, 12, 0);

      final txs = [
        Transaction(
          id: 1,
          amount: 800.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2026, 12, 31, 23, 30), // New Year's Eve
        ),
        Transaction(
          id: 2,
          amount: 300.0,
          type: 'income',
          projectId: 1,
          date: DateTime(2027, 1, 1, 01, 0), // New Year's Day
        ),
      ];

      final result = calculateDashboardData(txs, newYearsDayNow);

      expect(result.todayIncome, equals(300.0));
      expect(result.todayExpense, equals(0.0));
      expect(result.monthIncome, equals(300.0));
      expect(result.monthExpense, equals(0.0));
      expect(result.totalBalance, equals(1100.0));
    });

    test('8. Handles leap years correctly (Feb 29 2024)', () {
      final leapDayNow = DateTime(2024, 2, 29, 18, 0);

      final txs = [
        Transaction(
          id: 1,
          amount: 450.0,
          type: 'expense',
          projectId: 1,
          date: DateTime(2024, 2, 29, 10, 0), // Leap day
        ),
        Transaction(
          id: 2,
          amount: 200.0,
          type: 'expense',
          projectId: 1,
          date: DateTime(2024, 2, 28, 10, 0), // Feb 28
        ),
      ];

      final result = calculateDashboardData(txs, leapDayNow);

      expect(result.todayIncome, equals(0.0));
      expect(result.todayExpense, equals(450.0));
      expect(result.monthExpense, equals(650.0));
    });
  });

  group('dashboardProvider Stream integration with in-memory database', () {
    test('Refreshes automatically when transactions are added, edited, or deleted', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fixedNow = DateTime(2026, 10, 11, 12, 0);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dashboardClockProvider.overrideWithValue(fixedNow),
        ],
      );

      DashboardData? currentData;
      final subscription = container.listen<AsyncValue<DashboardData>>(
        dashboardProvider,
        (previous, next) {
          if (next.hasValue) {
            currentData = next.value;
          }
        },
        fireImmediately: true,
      );

      addTearDown(() {
        subscription.close();
        container.dispose();
        db.close();
      });

      final pId = await db.into(db.projects).insert(
            ProjectsCompanion.insert(name: 'Project Alpha'),
          );

      // Give stream time to process initial emit
      await Future.delayed(Duration.zero);
      expect(currentData, isNotNull);
      expect(currentData!.todayIncome, equals(0.0));
      expect(currentData!.todayExpense, equals(0.0));
      expect(currentData!.totalBalance, equals(0.0));

      // 2. Add today's income transaction
      final tId1 = await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              amount: 1200.0,
              type: 'income',
              projectId: pId,
              date: Value(DateTime(2026, 10, 11, 10, 0)),
            ),
          );

      await Future.delayed(Duration.zero);
      expect(currentData!.todayIncome, equals(1200.0));
      expect(currentData!.totalBalance, equals(1200.0));

      // 3. Edit transaction amount
      await (db.update(db.transactions)..where((t) => t.id.equals(tId1))).write(
        const TransactionsCompanion(amount: Value(1500.0)),
      );

      await Future.delayed(Duration.zero);
      expect(currentData!.todayIncome, equals(1500.0));
      expect(currentData!.totalBalance, equals(1500.0));

      // 4. Add future-dated transaction (should NOT affect today's or month's totals)
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              amount: 5000.0,
              type: 'income',
              projectId: pId,
              date: Value(DateTime(2026, 10, 25, 10, 0)), // Future date in current month
            ),
          );

      await Future.delayed(Duration.zero);
      expect(currentData!.todayIncome, equals(1500.0)); // Unchanged
      expect(currentData!.monthIncome, equals(1500.0)); // Unchanged
      expect(currentData!.totalBalance, equals(6500.0)); // Included in total balance

      // 5. Delete initial transaction
      await (db.delete(db.transactions)..where((t) => t.id.equals(tId1))).go();

      await Future.delayed(Duration.zero);
      expect(currentData!.todayIncome, equals(0.0));
      expect(currentData!.monthIncome, equals(0.0));
      expect(currentData!.totalBalance, equals(5000.0));
    });
  });
}
