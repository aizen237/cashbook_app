import 'dart:async';
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardData &&
          runtimeType == other.runtimeType &&
          todayIncome == other.todayIncome &&
          todayExpense == other.todayExpense &&
          totalBalance == other.totalBalance &&
          monthIncome == other.monthIncome &&
          monthExpense == other.monthExpense;

  @override
  int get hashCode =>
      todayIncome.hashCode ^
      todayExpense.hashCode ^
      totalBalance.hashCode ^
      monthIncome.hashCode ^
      monthExpense.hashCode;
}

/// Calculates dashboard totals deterministically given a list of transactions and a fixed [now] reference time.
DashboardData calculateDashboardData(
  List<Transaction> allTransactions,
  DateTime now,
) {
  final localNow = now.toLocal();
  final todayStart = DateTime(localNow.year, localNow.month, localNow.day);
  final monthStart = DateTime(localNow.year, localNow.month, 1);

  double todayIncome = 0;
  double todayExpense = 0;
  double monthIncome = 0;
  double monthExpense = 0;
  double totalIncome = 0;
  double totalExpense = 0;

  for (final t in allTransactions) {
    final txDate = t.date.toLocal();
    final isIncome = t.type == 'income';

    if (isIncome) {
      totalIncome += t.amount;
    } else {
      totalExpense += t.amount;
    }

    final isBeforeOrAtNow = !txDate.isAfter(localNow);

    if (isBeforeOrAtNow) {
      if (!txDate.isBefore(monthStart)) {
        if (isIncome) {
          monthIncome += t.amount;
        } else {
          monthExpense += t.amount;
        }
      }

      if (!txDate.isBefore(todayStart)) {
        if (isIncome) {
          todayIncome += t.amount;
        } else {
          todayExpense += t.amount;
        }
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
}

/// Provider supplying current reference time, refreshing periodically to update date boundaries.
final dashboardClockProvider = Provider<DateTime>((ref) {
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  return DateTime.now();
});

final dashboardProvider = StreamProvider<DashboardData>((ref) {
  final db = ref.watch(databaseProvider);
  final now = ref.watch(dashboardClockProvider);

  return db.select(db.transactions).watch().map((allTransactions) {
    return calculateDashboardData(allTransactions, now);
  });
});
