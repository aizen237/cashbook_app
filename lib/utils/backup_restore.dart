import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../database/database.dart';

class BackupResult {
  final bool success;
  final String message;
  final String? filePath;

  BackupResult(this.success, this.message, {this.filePath});
}

class _ReceiptToPack {
  final String zipPath;
  final List<int> bytes;
  _ReceiptToPack(this.zipPath, this.bytes);
}

/// Exports all database records and associated receipt images into a portable ZIP package.
Future<BackupResult> exportBackup(
  AppDatabase db, {
  Directory? targetDir,
  bool shareAfterExport = true,
}) async {
  try {
    final projects = await db.select(db.projects).get();
    final transactions = await db.select(db.transactions).get();

    final receiptsToPack = <_ReceiptToPack>[];
    final jsonTransactions = <Map<String, dynamic>>[];

    for (final t in transactions) {
      String? relativeReceiptPath;

      if (t.receiptImagePath != null && t.receiptImagePath!.trim().isNotEmpty) {
        final receiptFile = File(t.receiptImagePath!);
        if (receiptFile.existsSync()) {
          final fileName = p.basename(receiptFile.path);
          relativeReceiptPath = 'receipts/$fileName';
          final bytes = await receiptFile.readAsBytes();
          receiptsToPack.add(_ReceiptToPack(relativeReceiptPath, bytes));
        }
      }

      jsonTransactions.add({
        'id': t.id,
        'amount': t.amount,
        'type': t.type,
        'projectId': t.projectId,
        'description': t.description,
        'date': t.date.toIso8601String(),
        'paymentMethod': t.paymentMethod,
        'receiptImagePath': relativeReceiptPath,
      });
    }

    final backupData = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'projects': projects
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'createdAt': p.createdAt.toIso8601String(),
              })
          .toList(),
      'transactions': jsonTransactions,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
    final jsonBytes = utf8.encode(jsonString);

    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));

    for (final r in receiptsToPack) {
      archive.addFile(ArchiveFile(r.zipPath, r.bytes.length, r.bytes));
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'cashbook_backup_$timestamp.zip';

    String? outputFilePath;
    if (targetDir != null) {
      final outputFile = File(p.join(targetDir.path, fileName));
      await outputFile.writeAsBytes(zipBytes);
      outputFilePath = outputFile.path;
    }

    if (shareAfterExport) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(zipBytes),
        filename: fileName,
      );
    }

    return BackupResult(
      true,
      'Backup created successfully with ${projects.length} projects, ${transactions.length} transactions, and ${receiptsToPack.length} receipt images.',
      filePath: outputFilePath,
    );
  } catch (e) {
    return BackupResult(false, 'Export failed: $e');
  }
}

/// Restores database records and receipt images from a ZIP backup or legacy JSON backup.
Future<BackupResult> restoreBackup(
  AppDatabase db, {
  File? backupFile,
  Directory? targetStorageDir,
}) async {
  try {
    File? selectedFile = backupFile;

    if (selectedFile == null) {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip', 'json'],
      );

      if (picked == null || picked.path == null) {
        return BackupResult(false, 'No file selected.');
      }
      selectedFile = File(picked.path!);
    }

    if (!selectedFile.existsSync()) {
      return BackupResult(false, 'Backup file does not exist on disk.');
    }

    final fileBytes = await selectedFile.readAsBytes();
    if (fileBytes.isEmpty) {
      return BackupResult(false, 'Validation failed: Selected backup file is empty.');
    }

    final extension = p.extension(selectedFile.path).toLowerCase();

    if (extension == '.json') {
      return await _restoreFromLegacyJson(db, selectedFile);
    }

    // Attempt ZIP restoration
    try {
      final archive = ZipDecoder().decodeBytes(fileBytes);
      return await _restoreFromZipArchive(
        db,
        archive,
        targetStorageDir: targetStorageDir,
      );
    } catch (zipError) {
      // Fallback: Check if file was actually a JSON file named differently
      try {
        final content = utf8.decode(fileBytes);
        final jsonMap = jsonDecode(content);
        if (jsonMap is Map<String, dynamic> && jsonMap.containsKey('projects')) {
          return await _restoreFromLegacyJson(db, selectedFile);
        }
      } catch (_) {}

      return BackupResult(
          false, 'Validation failed: Invalid or corrupted ZIP archive ($zipError).');
    }
  } catch (e) {
    return BackupResult(false, 'Restore failed: $e');
  }
}

Future<BackupResult> _restoreFromZipArchive(
  AppDatabase db,
  Archive archive, {
  Directory? targetStorageDir,
}) async {
  ArchiveFile? jsonArchiveFile;
  final receiptEntries = <String, ArchiveFile>{};

  for (final file in archive) {
    final normPath = p.normalize(file.name).replaceAll('\\', '/');
    if (normPath == 'backup.json' || p.basename(normPath) == 'backup.json') {
      jsonArchiveFile = file;
    } else if (normPath.startsWith('receipts/') || file.name.contains('receipt')) {
      receiptEntries[normPath] = file;
      receiptEntries[p.basename(normPath)] = file;
    }
  }

  if (jsonArchiveFile == null) {
    return BackupResult(
        false, 'Validation failed: backup.json is missing in the ZIP archive.');
  }

  final jsonContentBytes = jsonArchiveFile.content as List<int>;
  if (jsonContentBytes.isEmpty) {
    return BackupResult(
        false, 'Validation failed: backup.json inside ZIP archive is empty.');
  }

  Map<String, dynamic> data;
  try {
    final jsonStr = utf8.decode(jsonContentBytes);
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      return BackupResult(false, 'Validation failed: backup.json content is invalid.');
    }
    data = decoded;
  } catch (e) {
    return BackupResult(
        false, 'Validation failed: Unable to parse backup.json ($e).');
  }

  final validationResult = _validateBackupStructure(data);
  if (!validationResult.success) {
    return validationResult;
  }

  final projectsJson = data['projects'] as List;
  final transactionsJson = data['transactions'] as List;

  // Validate that all referenced receipt images exist in ZIP archive and are non-empty
  for (final t in transactionsJson) {
    final receiptPath = t['receiptImagePath'] as String?;
    if (receiptPath != null && receiptPath.trim().isNotEmpty) {
      final normReceiptPath = p.normalize(receiptPath).replaceAll('\\', '/');
      final baseName = p.basename(normReceiptPath);

      final entry = receiptEntries[normReceiptPath] ?? receiptEntries[baseName];
      if (entry == null) {
        return BackupResult(
          false,
          'Validation failed: Referenced receipt image "$receiptPath" is missing from the ZIP backup archive.',
        );
      }
      final entryBytes = entry.content as List<int>;
      if (entryBytes.isEmpty) {
        return BackupResult(
          false,
          'Validation failed: Referenced receipt image "$receiptPath" inside ZIP is empty (0 bytes).',
        );
      }
    }
  }

  // All validation passed safely. Get target storage directory for receipts.
  Directory appDir;
  if (targetStorageDir != null) {
    appDir = targetStorageDir;
  } else {
    appDir = await getApplicationDocumentsDirectory();
  }

  if (!appDir.existsSync()) {
    await appDir.create(recursive: true);
  }

  // Extract receipt images to destination storage
  final restoredReceiptPaths = <String, String>{};
  for (final entry in receiptEntries.entries) {
    final archiveFile = entry.value;
    if (archiveFile.isFile && (archiveFile.content as List<int>).isNotEmpty) {
      final fileName = p.basename(archiveFile.name);
      final destFile = File(p.join(appDir.path, fileName));
      await destFile.writeAsBytes(archiveFile.content as List<int>);
      restoredReceiptPaths[archiveFile.name] = destFile.path;
      restoredReceiptPaths[p.normalize(archiveFile.name).replaceAll('\\', '/')] =
          destFile.path;
      restoredReceiptPaths[fileName] = destFile.path;
      restoredReceiptPaths['receipts/$fileName'] = destFile.path;
    }
  }

  // Database atomic swap inside transaction
  await db.transaction(() async {
    await db.delete(db.transactions).go();
    await db.delete(db.projects).go();

    final projectIdMap = <int, int>{};

    for (final pJson in projectsJson) {
      final oldId = pJson['id'] as int;
      final newId = await db.into(db.projects).insert(
            ProjectsCompanion.insert(
              name: pJson['name'] as String,
              createdAt: Value(DateTime.parse(pJson['createdAt'] as String)),
            ),
          );
      projectIdMap[oldId] = newId;
    }

    for (final tJson in transactionsJson) {
      final oldProjectId = tJson['projectId'] as int;
      final newProjectId = projectIdMap[oldProjectId];
      if (newProjectId == null) continue;

      String? newReceiptPath;
      final relPath = tJson['receiptImagePath'] as String?;
      if (relPath != null && relPath.trim().isNotEmpty) {
        final normRel = p.normalize(relPath).replaceAll('\\', '/');
        final baseName = p.basename(normRel);
        newReceiptPath = restoredReceiptPaths[normRel] ??
            restoredReceiptPaths[baseName] ??
            restoredReceiptPaths[relPath];
      }

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              amount: (tJson['amount'] as num).toDouble(),
              type: tJson['type'] as String,
              projectId: newProjectId,
              description: Value(tJson['description'] as String?),
              date: Value(DateTime.parse(tJson['date'] as String)),
              paymentMethod: Value(tJson['paymentMethod'] as String?),
              receiptImagePath: Value(newReceiptPath),
            ),
          );
    }
  });

  return BackupResult(
    true,
    'Restored ${projectsJson.length} projects, ${transactionsJson.length} transactions, and ${restoredReceiptPaths.length} receipt images successfully.',
  );
}

Future<BackupResult> _restoreFromLegacyJson(
  AppDatabase db,
  File jsonFile,
) async {
  Map<String, dynamic> data;
  try {
    final content = await jsonFile.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      return BackupResult(false, 'Validation failed: Invalid JSON structure.');
    }
    data = decoded;
  } catch (e) {
    return BackupResult(false, 'Validation failed: Unable to read JSON ($e).');
  }

  final validationResult = _validateBackupStructure(data);
  if (!validationResult.success) {
    return validationResult;
  }

  final projectsJson = data['projects'] as List;
  final transactionsJson = data['transactions'] as List;

  await db.transaction(() async {
    await db.delete(db.transactions).go();
    await db.delete(db.projects).go();

    final projectIdMap = <int, int>{};

    for (final pJson in projectsJson) {
      final oldId = pJson['id'] as int;
      final newId = await db.into(db.projects).insert(
            ProjectsCompanion.insert(
              name: pJson['name'] as String,
              createdAt: Value(DateTime.parse(pJson['createdAt'] as String)),
            ),
          );
      projectIdMap[oldId] = newId;
    }

    for (final tJson in transactionsJson) {
      final oldProjectId = tJson['projectId'] as int;
      final newProjectId = projectIdMap[oldProjectId];
      if (newProjectId == null) continue;

      String? validReceiptPath;
      final origPath = tJson['receiptImagePath'] as String?;
      if (origPath != null && origPath.trim().isNotEmpty) {
        final existingFile = File(origPath);
        if (existingFile.existsSync()) {
          validReceiptPath = existingFile.path;
        }
      }

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              amount: (tJson['amount'] as num).toDouble(),
              type: tJson['type'] as String,
              projectId: newProjectId,
              description: Value(tJson['description'] as String?),
              date: Value(DateTime.parse(tJson['date'] as String)),
              paymentMethod: Value(tJson['paymentMethod'] as String?),
              receiptImagePath: Value(validReceiptPath),
            ),
          );
    }
  });

  return BackupResult(
    true,
    'Restored ${projectsJson.length} projects and ${transactionsJson.length} transactions from legacy JSON backup. Note: Receipt images cannot be recovered from legacy JSON backups.',
  );
}

BackupResult _validateBackupStructure(Map<String, dynamic> data) {
  if (!data.containsKey('version') || data['version'] == null) {
    return BackupResult(
        false, 'Validation failed: Missing version in backup data.');
  }

  if (!data.containsKey('projects') || data['projects'] is! List) {
    return BackupResult(
        false, 'Validation failed: Missing or invalid projects list.');
  }

  if (!data.containsKey('transactions') || data['transactions'] is! List) {
    return BackupResult(
        false, 'Validation failed: Missing or invalid transactions list.');
  }

  final projects = data['projects'] as List;
  final projectIds = <int>{};

  for (final p in projects) {
    if (p is! Map<String, dynamic>) {
      return BackupResult(
          false, 'Validation failed: Corrupted project record structure.');
    }
    final id = p['id'];
    final name = p['name'];
    final createdAt = p['createdAt'];

    if (id is! int || name is! String || name.trim().isEmpty || createdAt is! String) {
      return BackupResult(
          false, 'Validation failed: Invalid project fields in backup.');
    }

    try {
      DateTime.parse(createdAt);
    } catch (_) {
      return BackupResult(
          false, 'Validation failed: Invalid project creation date format.');
    }

    projectIds.add(id);
  }

  final transactions = data['transactions'] as List;

  for (final t in transactions) {
    if (t is! Map<String, dynamic>) {
      return BackupResult(
          false, 'Validation failed: Corrupted transaction record structure.');
    }

    final id = t['id'];
    final amount = t['amount'];
    final type = t['type'];
    final projectId = t['projectId'];
    final date = t['date'];

    if (id is! int ||
        amount is! num ||
        amount < 0 ||
        type is! String ||
        (type != 'income' && type != 'expense') ||
        projectId is! int ||
        date is! String) {
      return BackupResult(
          false, 'Validation failed: Invalid transaction fields in backup.');
    }

    try {
      DateTime.parse(date);
    } catch (_) {
      return BackupResult(
          false, 'Validation failed: Invalid transaction date format.');
    }

    if (!projectIds.contains(projectId)) {
      return BackupResult(
        false,
        'Validation failed: Transaction references non-existent project (ID: $projectId).',
      );
    }
  }

  return BackupResult(true, 'Validation successful.');
}
