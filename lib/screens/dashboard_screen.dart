import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/receipt_viewer.dart';
import 'add_transaction_screen.dart';


class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);
    final transactionsAsync = ref.watch(transactionsProvider);


    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: dashboardAsync.when(
        data: (data) {
          final recentTransactions =
          (transactionsAsync.value ?? []).take(5).toList();


          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Balance card
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('Current Balance'),
                      const SizedBox(height: 8),
                      Text(
                        'ETB ${data.totalBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Today's income/expense
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: "Today's Income",
                      amount: data.todayIncome,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: "Today's Expense",
                      amount: data.todayExpense,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Month's income/expense
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: "This Month Income",
                      amount: data.monthIncome,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: "This Month Expense",
                      amount: data.monthExpense,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const Text(
                'Recent Transactions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              if (recentTransactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No transactions yet')),
                )
              else
                ...recentTransactions.map((t) {

                  final isIncome = t.type == 'income';

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isIncome
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      child: Icon(
                        isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isIncome ? Colors.green : Colors.red,
                      ),
                    ),
                    title: Text(t.description ?? 'No description'),
                    subtitle: Text(
                      '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (t.receiptImagePath != null &&
                            t.receiptImagePath!.isNotEmpty &&
                            File(t.receiptImagePath!).existsSync())
                          IconButton(
                            icon: const Icon(Icons.receipt_long_outlined,
                                color: Colors.blueAccent),
                            tooltip: 'View Receipt',
                            onPressed: () => ReceiptViewerDialog.show(
                                context, t.receiptImagePath!),
                          ),
                        Text(
                          '${isIncome ? '+' : '-'}ETB ${t.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isIncome ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AddTransactionScreen(
                            projectId: t.projectId,
                            existingTransaction: t,
                          ),
                        ),
                      );
                    },
                  );
                }),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _StatCard({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              'ETB ${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}