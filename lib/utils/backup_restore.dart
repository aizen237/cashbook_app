import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../database/database.dart';

class BackupResult {
  final bool success;
  final String message;
  BackupResult(this.success, this.message);
}

Future<BackupResult> exportBackup(AppDatabase db) async {
  try {
    final projects = await db.select(db.projects).get();
    final transactions = await db.select(db.transactions).get();

    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'projects': projects
          .map((p) => {
        'id': p.id,
        'name': p.name,
        'createdAt': p.createdAt.toIso8601String(),
      })
          .toList(),
      'transactions': transactions
          .map((t) => {
        'id': t.id,
        'amount': t.amount,
        'type': t.type,
        'projectId': t.projectId,
        'description': t.description,
        'date': t.date.toIso8601String(),
        'paymentMethod': t.paymentMethod,
        'receiptImagePath': t.receiptImagePath,
      })
          .toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(jsonString);

    final fileName =
        'cashbook_backup_${DateTime.now().millisecondsSinceEpoch}.json';

    await Printing.sharePdf(bytes: bytes, filename: fileName);

    return BackupResult(true, 'Backup created and ready to share/save.');
  } catch (e) {
    return BackupResult(false, 'Backup failed: $e');
  }
}

Future<BackupResult> restoreBackup(AppDatabase db) async {
  try {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (picked == null || picked.path == null) {
      return BackupResult(false, 'No file selected.');
    }

    final file = File(picked.path!);
    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    final projectsJson = data['projects'] as List;
    final transactionsJson = data['transactions'] as List;

    await db.transaction(() async {
      await db.delete(db.transactions).go();
      await db.delete(db.projects).go();

      final projectIdMap = <int, int>{};

      for (final p in projectsJson) {
        final newId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            name: p['name'] as String,
            createdAt: Value(DateTime.parse(p['createdAt'] as String)),
          ),
        );
        projectIdMap[p['id'] as int] = newId;
      }

      for (final t in transactionsJson) {
        final oldProjectId = t['projectId'] as int;
        final newProjectId = projectIdMap[oldProjectId];
        if (newProjectId == null) continue;

        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            amount: (t['amount'] as num).toDouble(),
            type: t['type'] as String,
            projectId: newProjectId,
            description: Value(t['description'] as String?),
            date: Value(DateTime.parse(t['date'] as String)),
            paymentMethod: Value(t['paymentMethod'] as String?),
            receiptImagePath: Value(t['receiptImagePath'] as String?),
          ),
        );
      }
    });

    return BackupResult(true,
        'Restored ${projectsJson.length} projects and ${transactionsJson.length} transactions.');
  } catch (e) {
    return BackupResult(false, 'Restore failed: $e');
  }
}