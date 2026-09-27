import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import 'database_provider.dart';

class DashboardData {
  final double todayIncome;
  final double todayExpense;
  final double totalBalance;
  final double monthIncome;
  final double monthExpense;

  DashboardData({
    required this.todayIncome,
    required this.todayExpense,
    required this.totalBalance,
    required this.monthIncome,
    required this.monthExpense,
  });
}

final dashboardProvider = StreamProvider<DashboardData>((ref) {
  final db = ref.watch(databaseProvider);

  return db.select(db.transactions).watch().map((allTransactions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);

    double todayIncome = 0;
    double todayExpense = 0;
    double monthIncome = 0;
    double monthExpense = 0;
    double totalIncome = 0;
    double totalExpense = 0;

    for (final t in allTransactions) {
      final isIncome = t.type == 'income';

      if (isIncome) {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }

      if (t.date.isAfter(monthStart) ||
          t.date.isAtSameMomentAs(monthStart)) {
        if (isIncome) {
          monthIncome += t.amount;
        } else {
          monthExpense += t.amount;
        }
      }

      if (t.date.isAfter(todayStart) ||
          t.date.isAtSameMomentAs(todayStart)) {
        if (isIncome) {
          todayIncome += t.amount;
        } else {
          todayExpense += t.amount;
        }
      }
    }

    return DashboardData(
      todayIncome: todayIncome,
      todayExpense: todayExpense,
      totalBalance: totalIncome - totalExpense,
      monthIncome: monthIncome,
      monthExpense: monthExpense,
    );
  });
});