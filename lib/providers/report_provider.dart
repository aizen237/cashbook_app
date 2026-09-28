import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../database/database.dart';
import 'database_provider.dart';

class ReportFilter {
  final int? projectId; // null = all projects
  final DateTime? fromDate;
  final DateTime? toDate;
  final String descriptionQuery;

  const ReportFilter({
    this.projectId,
    this.fromDate,
    this.toDate,
    this.descriptionQuery = '',
  });

  ReportFilter copyWith({
    int? projectId,
    bool clearProjectId = false,
    DateTime? fromDate,
    bool clearFromDate = false,
    DateTime? toDate,
    bool clearToDate = false,
    String? descriptionQuery,
  }) {
    return ReportFilter(
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      descriptionQuery: descriptionQuery ?? this.descriptionQuery,
    );
  }
}

final reportFilterProvider =
StateProvider<ReportFilter>((ref) => const ReportFilter());

class ReportResult {
  final List<Transaction> transactions;
  final double totalIncome;
  final double totalExpense;

  ReportResult({
    required this.transactions,
    required this.totalIncome,
    required this.totalExpense,
  });

  double get netBalance => totalIncome - totalExpense;
}

final reportResultProvider = StreamProvider<ReportResult>((ref) {
  final db = ref.watch(databaseProvider);
  final filter = ref.watch(reportFilterProvider);

  return db.select(db.transactions).watch().map((allTransactions) {
    var filtered = allTransactions;

    if (filter.projectId != null) {
      filtered =
          filtered.where((t) => t.projectId == filter.projectId).toList();
    }

    if (filter.fromDate != null) {
      final from = DateTime(
        filter.fromDate!.year,
        filter.fromDate!.month,
        filter.fromDate!.day,
      );
      filtered = filtered.where((t) => !t.date.isBefore(from)).toList();
    }

    if (filter.toDate != null) {
      final to = DateTime(
        filter.toDate!.year,
        filter.toDate!.month,
        filter.toDate!.day,
        23,
        59,
        59,
      );
      filtered = filtered.where((t) => !t.date.isAfter(to)).toList();
    }

    if (filter.descriptionQuery.isNotEmpty) {
      final query = filter.descriptionQuery.toLowerCase();
      filtered = filtered
          .where((t) => (t.description ?? '').toLowerCase().contains(query))
          .toList();
    }

    filtered.sort((a, b) => b.date.compareTo(a.date));

    double totalIncome = 0;
    double totalExpense = 0;
    for (final t in filtered) {
      if (t.type == 'income') {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }
    }

    return ReportResult(
      transactions: filtered,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
    );
  });
});