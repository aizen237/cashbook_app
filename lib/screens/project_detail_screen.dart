import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../providers/project_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/category_provider.dart';
import 'add_transaction_screen.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final Project project;

  const ProjectDetailScreen({super.key, required this.project});

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  String _searchQuery = '';
  DateTime? _filterDate;

  @override
  Widget build(BuildContext context) {
    final transactionsAsync =
    ref.watch(projectTransactionsProvider(widget.project.id));
    final totalsAsync = ref.watch(projectTotalsProvider(widget.project.id));
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.value ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(widget.project.name)),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  AddTransactionScreen(projectId: widget.project.id),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Totals header
          totalsAsync.when(
            data: (totals) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _TotalStat(
                      label: 'Income',
                      amount: totals.income,
                      color: Colors.green),
                  _TotalStat(
                      label: 'Expense',
                      amount: totals.expense,
                      color: Colors.red),
                  _TotalStat(
                    label: 'Balance',
                    amount: totals.balance,
                    color: totals.balance >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
          ),

          // Search + date filter
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search description...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _searchQuery = value.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _filterDate == null
                        ? Icons.calendar_today_outlined
                        : Icons.calendar_today,
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _filterDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    setState(() => _filterDate = picked);
                  },
                ),
                if (_filterDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _filterDate = null),
                  ),
              ],
            ),
          ),

          // Transaction list
          Expanded(
            child: transactionsAsync.when(
              data: (transactions) {
                var filtered = transactions;

                if (_searchQuery.isNotEmpty) {
                  filtered = filtered
                      .where((t) =>
                      (t.description ?? '')
                          .toLowerCase()
                          .contains(_searchQuery))
                      .toList();
                }

                if (_filterDate != null) {
                  filtered = filtered
                      .where((t) =>
                  t.date.year == _filterDate!.year &&
                      t.date.month == _filterDate!.month &&
                      t.date.day == _filterDate!.day)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return const Center(child: Text('No transactions found'));
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final t = filtered[index];
                    final category = categories
                        .where((c) => c.id == t.categoryId)
                        .cast()
                        .firstOrNull;
                    final isIncome = t.type == 'income';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isIncome
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        child: Icon(
                          isIncome
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                      title: Text(category?.name ?? 'Unknown'),
                      subtitle: Text(
                        '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}'
                            '${t.description != null ? ' • ${t.description}' : ''}',
                      ),
                      trailing: Text(
                        '${isIncome ? '+' : '-'}ETB ${t.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                      onLongPress: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete transaction?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref
                              .read(transactionActionsProvider)
                              .deleteTransaction(t.id);
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalStat extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _TotalStat({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          'ETB ${amount.toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}