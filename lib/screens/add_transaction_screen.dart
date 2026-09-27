import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final int projectId;

  const AddTransactionScreen({super.key, required this.projectId});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _type = 'expense';
  Category? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  String? _paymentMethod;

  final List<String> _paymentMethods = ['Cash', 'Bank Transfer', 'Mobile Money'];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a category')),
      );
      return;
    }

    final actions = ref.read(transactionActionsProvider);
    await actions.addTransaction(
      TransactionInput(
        amount: amount,
        type: _type,
        categoryId: _selectedCategory!.id,
        projectId: widget.projectId,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        date: _selectedDate,
        paymentMethod: _paymentMethod,
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Income / Expense toggle
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() {
                  _type = selection.first;
                  _selectedCategory = null; // reset category on type change
                });
              },
            ),
            const SizedBox(height: 20),

            // Amount
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: 'ETB ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Category dropdown
            categoriesAsync.when(
              data: (categories) {
                final filtered =
                categories.where((c) => c.type == _type).toList();
                return DropdownButtonFormField<Category>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: filtered
                      .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c.name),
                  ))
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedCategory = value);
                  },
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error loading categories: $e'),
            ),
            const SizedBox(height: 20),

            // Date picker
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Payment method
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment Method (optional)',
                border: OutlineInputBorder(),
              ),
              items: _paymentMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (value) {
                setState(() => _paymentMethod = value);
              },
            ),
            const SizedBox(height: 20),

            // Description
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 32),

            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save Transaction', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}