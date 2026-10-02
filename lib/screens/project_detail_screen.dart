import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../providers/project_provider.dart';
import '../providers/transaction_provider.dart';
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
  DateTime? _fromDate;
  DateTime? _toDate;

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final dateFormatted = '${date.day} ${months[date.month - 1]} ${date.year}';

    if (diff == 0) {
      return 'Today ($dateFormatted)';
    } else if (diff == 1) {
      return 'Yesterday ($dateFormatted)';
    } else if (diff == -1) {
      return 'Tomorrow ($dateFormatted)';
    } else if (diff > 1 && diff <= 7) {
      return '$diff days ago ($dateFormatted)';
    } else {
      return dateFormatted;
    }
  }

  Widget _buildDateSeparator(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: Theme.of(context).colorScheme.outlineVariant,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProjectDialog(
      BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project name',
            hintText: 'e.g. Residential House',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await ref
          .read(projectActionsProvider)
          .updateProject(widget.project.id, newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectProvider(widget.project.id));
    final currentProjectName =
        projectAsync.value?.name ?? widget.project.name;

    final transactionsAsync =
        ref.watch(projectTransactionsProvider(widget.project.id));
    final totalsAsync = ref.watch(projectTotalsProvider(widget.project.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(currentProjectName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Project',
            onPressed: () => _editProjectDialog(context, currentProjectName),
          ),
        ],
      ),
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
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _fromDate = picked);
                  },
                  child: Text(
                    _fromDate == null
                        ? 'From'
                        : '${_fromDate!.year}-${_fromDate!.month.toString().padLeft(2, '0')}-${_fromDate!.day.toString().padLeft(2, '0')}',
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _toDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _toDate = picked);
                  },
                  child: Text(
                    _toDate == null
                        ? 'To'
                        : '${_toDate!.year}-${_toDate!.month.toString().padLeft(2, '0')}-${_toDate!.day.toString().padLeft(2, '0')}',
                  ),
                ),
                if (_fromDate != null || _toDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _fromDate = null;
                      _toDate = null;
                    }),
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

                if (_fromDate != null) {
                  final from = DateTime(
                      _fromDate!.year, _fromDate!.month, _fromDate!.day);
                  filtered =
                      filtered.where((t) => !t.date.isBefore(from)).toList();
                }

                if (_toDate != null) {
                  final to = DateTime(_toDate!.year, _toDate!.month,
                      _toDate!.day, 23, 59, 59);
                  filtered =
                      filtered.where((t) => !t.date.isAfter(to)).toList();
                }

                if (filtered.isEmpty) {
                  return const Center(child: Text('No transactions found'));
                }

                // Group transactions by date
                final Map<DateTime, List<Transaction>> groupedMap = {};
                for (final t in filtered) {
                  final dateKey =
                      DateTime(t.date.year, t.date.month, t.date.day);
                  groupedMap.putIfAbsent(dateKey, () => []).add(t);
                }

                final listItems = <dynamic>[];
                for (final entry in groupedMap.entries) {
                  listItems.add(entry.key); // DateTime
                  listItems.addAll(entry.value); // Transactions
                }

                return ListView.builder(
                  itemCount: listItems.length,
                  itemBuilder: (context, index) {
                    final item = listItems[index];

                    if (item is DateTime) {
                      return _buildDateSeparator(_formatDateHeader(item));
                    }

                    final t = item as Transaction;
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
                      title: Text(t.description ?? 'No description'),
                      subtitle: Text(
                        t.paymentMethod != null &&
                                t.paymentMethod!.trim().isNotEmpty
                            ? t.paymentMethod!
                            : 'No payment method',
                      ),
                      trailing: Text(
                        '${isIncome ? '+' : '-'}ETB ${t.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddTransactionScreen(
                              projectId: widget.project.id,
                              existingTransaction: t,
                            ),
                          ),
                        );
                      },
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