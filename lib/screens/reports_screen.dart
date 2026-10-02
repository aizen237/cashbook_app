import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/report_provider.dart';
import '../providers/project_provider.dart';
import '../utils/pdf_report_generator.dart';
import 'add_transaction_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickFromDate() async {
    final filter = ref.read(reportFilterProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: filter.fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      ref.read(reportFilterProvider.notifier).state =
          filter.copyWith(fromDate: picked);
    }
  }

  Future<void> _pickToDate() async {
    final filter = ref.read(reportFilterProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: filter.toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      ref.read(reportFilterProvider.notifier).state =
          filter.copyWith(toDate: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(reportFilterProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final resultAsync = ref.watch(reportResultProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Project dropdown
            projectsAsync.when(
              data: (projects) => DropdownButtonFormField<int?>(
                initialValue: filter.projectId,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Projects')),
                  ...projects.map(
                        (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ),
                ],
                onChanged: (value) {
                  ref.read(reportFilterProvider.notifier).state = value == null
                      ? filter.copyWith(clearProjectId: true)
                      : filter.copyWith(projectId: value);
                },
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
            ),
            const SizedBox(height: 12),

            // Date range
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickFromDate,
                    child: Text(
                      filter.fromDate == null
                          ? 'From date'
                          : _formatDate(filter.fromDate!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickToDate,
                    child: Text(
                      filter.toDate == null
                          ? 'To date'
                          : _formatDate(filter.toDate!),
                    ),
                  ),
                ),
                if (filter.fromDate != null || filter.toDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      ref.read(reportFilterProvider.notifier).state =
                          filter.copyWith(clearFromDate: true, clearToDate: true);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Description search
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Search description',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                ref.read(reportFilterProvider.notifier).state =
                    filter.copyWith(descriptionQuery: value);
              },
            ),
            const SizedBox(height: 16),

            Expanded(
              child: resultAsync.when(
                data: (result) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _SummaryStat(
                              label: 'Income',
                              amount: result.totalIncome,
                              color: Colors.green,
                            ),
                            _SummaryStat(
                              label: 'Expense',
                              amount: result.totalExpense,
                              color: Colors.red,
                            ),
                            _SummaryStat(
                              label: 'Net',
                              amount: result.netBalance,
                              color: result.netBalance >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Export as PDF'),
                      onPressed: result.transactions.isEmpty
                          ? null
                          : () async {
                        final projects = projectsAsync.value ?? [];
                        final projectName = filter.projectId == null
                            ? 'All Projects'
                            : projects
                            .where((p) => p.id == filter.projectId)
                            .cast()
                            .firstOrNull
                            ?.name ??
                            'Unknown';

                        await generateAndShareReportPdf(
                          result: result,
                          projectName: projectName,
                          fromDate: filter.fromDate,
                          toDate: filter.toDate,
                          descriptionQuery: filter.descriptionQuery,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: result.transactions.isEmpty
                          ? const Center(child: Text('No transactions found'))
                          : ListView.builder(
                        itemCount: result.transactions.length,
                        itemBuilder: (context, index) {
                          final t = result.transactions[index];
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
                                color:
                                isIncome ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(t.description ?? 'No description'),
                            subtitle: Text(_formatDate(t.date)),
                            trailing: Text(
                              '${isIncome ? '+' : '-'}ETB ${t.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isIncome
                                    ? Colors.green
                                    : Colors.red,
                              ),
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
                        },
                      ),
                    ),
                  ],
                ),
                loading: () =>
                const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _SummaryStat({
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