import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../providers/transaction_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final int projectId;
  final Transaction? existingTransaction;

  const AddTransactionScreen({
    super.key,
    required this.projectId,
    this.existingTransaction,
  });

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;

  late String _type;
  late DateTime _selectedDate;
  String? _paymentMethod;

  final List<String> _paymentMethods = ['Cash', 'Bank Transfer', 'Mobile Money'];

  bool get _isEditing => widget.existingTransaction != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTransaction;

    _amountController = TextEditingController(
      text: existing != null ? existing.amount.toString() : '',
    );
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _type = existing?.type ?? 'expense';
    _selectedDate = existing?.date ?? DateTime.now();
    _paymentMethod = (existing != null &&
            existing.paymentMethod != null &&
            _paymentMethods.contains(existing.paymentMethod))
        ? existing.paymentMethod
        : null;
  }

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

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a description')),
      );
      return;
    }

    final input = TransactionInput(
      amount: amount,
      type: _type,
      projectId: widget.existingTransaction?.projectId ?? widget.projectId,
      description: _descriptionController.text.trim(),
      date: _selectedDate,
      paymentMethod: _paymentMethod,
    );

    final actions = ref.read(transactionActionsProvider);

    if (_isEditing) {
      await actions.updateTransaction(widget.existingTransaction!.id, input);
    } else {
      await actions.addTransaction(input);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) {
                setState(() => _type = selection.first);
              },
            ),
            const SizedBox(height: 20),

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

            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'e.g. Cement bags, Client advance payment',
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
              child: Text(
                _isEditing ? 'Update Transaction' : 'Save Transaction',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}