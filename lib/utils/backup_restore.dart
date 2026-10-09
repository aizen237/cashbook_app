import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database.dart';

const int kMaxSupportedVersion = 2;
const int kMaxZipFileCount = 10000;
const int kMaxSingleUncompressedSizeBytes = 100 * 1024 * 1024; // 100 MB
const int kMaxTotalUncompressedSizeBytes = 1 * 1024 * 1024 * 1024; // 1 GB

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

typedef ShareHandler = Future<ShareResult> Function(
    List<XFile> files, {String? text});

/// Exports database records and associated receipt images into a portable ZIP package.
Future<BackupResult> exportBackup(
  AppDatabase db, {
  Directory? targetDir,
  bool shareAfterExport = true,
  ShareHandler? shareHandler,
}) async {
  File? createdOutputFile;
  try {
    final projects = await db.select(db.projects).get();
    final transactions = await db.select(db.transactions).get();

    final receiptsToPack = <_ReceiptToPack>[];
    final jsonTransactions = <Map<String, dynamic>>[];
    final seenZipPaths = <String>{};

    for (final t in transactions) {
      String? relativeReceiptPath;

      if (t.receiptImagePath != null && t.receiptImagePath!.trim().isNotEmpty) {
        final receiptFile = File(t.receiptImagePath!);

        if (!receiptFile.existsSync()) {
          return BackupResult(
            false,
            'Export failed: Transaction ID ${t.id} ("${t.description ?? 'No description'}") references receipt image "${t.receiptImagePath}" which is missing from disk.',
          );
        }

        List<int> bytes;
        try {
          bytes = await receiptFile.readAsBytes();
          if (bytes.isEmpty) {
            return BackupResult(
              false,
              'Export failed: Transaction ID ${t.id} ("${t.description ?? 'No description'}") references receipt image "${t.receiptImagePath}" which is empty (0 bytes).',
            );
          }
        } catch (e) {
          return BackupResult(
            false,
            'Export failed: Transaction ID ${t.id} ("${t.description ?? 'No description'}") references receipt image "${t.receiptImagePath}" which cannot be read ($e).',
          );
        }

        final originalName = p.basename(receiptFile.path);
        var candidateZipPath = 'receipts/tx_${t.id}_$originalName';
        var counter = 1;
        while (seenZipPaths.contains(candidateZipPath)) {
          candidateZipPath = 'receipts/tx_${t.id}_${counter}_$originalName';
          counter++;
        }

        seenZipPaths.add(candidateZipPath);
        relativeReceiptPath = candidateZipPath;
        receiptsToPack.add(_ReceiptToPack(relativeReceiptPath, bytes));
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
          .map((pRecord) => {
                'id': pRecord.id,
                'name': pRecord.name,
                'createdAt': pRecord.createdAt.toIso8601String(),
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

    final zipBytes = ZipEncoder().encode(archive);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'cashbook_backup_$timestamp.zip';

    final outputFolder = targetDir ?? await _safeGetTemporaryDirectory();
    if (!outputFolder.existsSync()) {
      await outputFolder.create(recursive: true);
    }

    createdOutputFile = File(p.join(outputFolder.path, fileName));
    await createdOutputFile.writeAsBytes(zipBytes);

    if (shareAfterExport) {
      final xFile = XFile(
        createdOutputFile.path,
        mimeType: 'application/zip',
        name: fileName,
      );

      // ignore: deprecated_member_use
      final handler = shareHandler ?? Share.shareXFiles;
      final result = await handler(
        [xFile],
        text: 'Cashbook Backup Package',
      );

      if (result.status == ShareResultStatus.dismissed && targetDir == null) {
        if (createdOutputFile.existsSync()) {
          await createdOutputFile.delete();
        }
        return BackupResult(false, 'Backup share cancelled by user.');
      }
    }

    return BackupResult(
      true,
      'Backup created successfully with ${projects.length} projects, ${transactions.length} transactions, and ${receiptsToPack.length} receipt images.',
      filePath: createdOutputFile.path,
    );
  } catch (e) {
    if (createdOutputFile != null && createdOutputFile.existsSync() && targetDir == null) {
      try {
        await createdOutputFile.delete();
      } catch (_) {}
    }
    return BackupResult(false, 'Export failed: $e');
  }
}

/// Restores database records and receipt images from a ZIP backup or legacy JSON backup.
Future<BackupResult> restoreBackup(
  AppDatabase db, {
  File? backupFile,
  Directory? targetStorageDir,
  Directory? stagingParentDir,
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
      return BackupResult(
          false, 'Validation failed: Selected backup file is empty (0 bytes).');
    }

    final extension = p.extension(selectedFile.path).toLowerCase();

    if (extension == '.json') {
      return await _restoreFromLegacyJson(db, selectedFile);
    }

    try {
      final archive = ZipDecoder().decodeBytes(fileBytes);
      return await _restoreFromZipArchive(
        db,
        archive,
        targetStorageDir: targetStorageDir,
        stagingParentDir: stagingParentDir,
      );
    } catch (zipError) {
      if (zipError is BackupResult) {
        return zipError;
      }
      try {
        final content = utf8.decode(fileBytes);
        final jsonMap = jsonDecode(content);
        if (jsonMap is Map<String, dynamic> && jsonMap.containsKey('projects')) {
          return await _restoreFromLegacyJson(db, selectedFile);
        }
      } catch (_) {}

      return BackupResult(
        false,
        'Validation failed: Invalid or corrupted ZIP archive ($zipError).',
      );
    }
  } catch (e) {
    return BackupResult(false, 'Restore failed: $e');
  }
}

Future<BackupResult> _restoreFromZipArchive(
  AppDatabase db,
  Archive archive, {
  Directory? targetStorageDir,
  Directory? stagingParentDir,
}) async {
  if (archive.length > kMaxZipFileCount) {
    return BackupResult(
      false,
      'Validation failed: ZIP archive contains too many files (${archive.length} > $kMaxZipFileCount).',
    );
  }

  ArchiveFile? jsonArchiveFile;
  final zipEntriesMap = <String, ArchiveFile>{};
  final seenPaths = <String>{};
  int totalUncompressedBytes = 0;

  for (final file in archive) {
    final rawName = file.name;
    final normPath = p.normalize(rawName).replaceAll('\\', '/');

    // Zip Slip / Unsafe Archive Path Check
    if (normPath.startsWith('/') ||
        normPath.startsWith('../') ||
        normPath.contains('/../') ||
        normPath.contains(':\\') ||
        normPath.contains(':/')) {
      return BackupResult(
        false,
        'Validation failed: Unsafe archive path detected ("$rawName").',
      );
    }

    if (seenPaths.contains(normPath)) {
      return BackupResult(
        false,
        'Validation failed: Duplicate entry detected in ZIP archive ("$rawName").',
      );
    }
    seenPaths.add(normPath);

    final fileSize = file.size;
    if (fileSize > kMaxSingleUncompressedSizeBytes) {
      return BackupResult(
        false,
        'Validation failed: Single file "$rawName" in ZIP exceeds size limit ($fileSize bytes).',
      );
    }

    totalUncompressedBytes += fileSize;
    if (totalUncompressedBytes > kMaxTotalUncompressedSizeBytes) {
      return BackupResult(
        false,
        'Validation failed: Total uncompressed size of ZIP archive exceeds limit.',
      );
    }

    if (normPath == 'backup.json' || p.basename(normPath) == 'backup.json') {
      jsonArchiveFile = file;
    } else {
      zipEntriesMap[normPath] = file;
      zipEntriesMap[p.basename(normPath)] = file;
    }
  }

  if (jsonArchiveFile == null) {
    return BackupResult(
      false,
      'Validation failed: backup.json is missing in the ZIP archive.',
    );
  }

  final jsonContentBytes = jsonArchiveFile.content as List<int>;
  if (jsonContentBytes.isEmpty) {
    return BackupResult(
      false,
      'Validation failed: backup.json inside ZIP archive is empty.',
    );
  }

  Map<String, dynamic> data;
  try {
    final jsonStr = utf8.decode(jsonContentBytes);
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      return BackupResult(
        false,
        'Validation failed: backup.json content is not a JSON object.',
      );
    }
    data = decoded;
  } catch (e) {
    return BackupResult(
      false,
      'Validation failed: Unable to parse backup.json ($e).',
    );
  }

  final validationResult = _validateBackupStructure(data);
  if (!validationResult.success) {
    return validationResult;
  }

  final projectsJson = data['projects'] as List;
  final transactionsJson = data['transactions'] as List;

  // Validate every referenced receipt image exists in ZIP and is non-empty
  for (final t in transactionsJson) {
    final receiptPath = t['receiptImagePath'] as String?;
    if (receiptPath != null && receiptPath.trim().isNotEmpty) {
      final normReceiptPath = p.normalize(receiptPath).replaceAll('\\', '/');
      final baseName = p.basename(normReceiptPath);

      final entry = zipEntriesMap[normReceiptPath] ?? zipEntriesMap[baseName];
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

  // Stage receipts in a temporary staging directory first
  Directory? stagingDir;
  final newlyCreatedDestFiles = <File>[];

  try {
    final stagingParent = stagingParentDir ?? await _safeGetTemporaryDirectory();
    stagingDir = await stagingParent.createTemp('cashbook_restore_staging_');

    final stagedReceiptMap = <String, File>{};

    for (final entry in zipEntriesMap.entries) {
      final archiveFile = entry.value;
      if (archiveFile.isFile && (archiveFile.content as List<int>).isNotEmpty) {
        final fileName = p.basename(archiveFile.name);
        final stagedFile = File(p.join(stagingDir.path, fileName));
        await stagedFile.writeAsBytes(archiveFile.content as List<int>);
        stagedReceiptMap[entry.key] = stagedFile;
      }
    }

    final destDir =
        targetStorageDir ?? await _safeGetApplicationDocumentsDirectory();
    if (!destDir.existsSync()) {
      await destDir.create(recursive: true);
    }

    // Copy staged receipts to destination with unique, collision-safe filenames
    final finalReceiptPathsMap = <String, String>{};

    for (final entry in stagedReceiptMap.entries) {
      final key = entry.key;
      final stagedFile = entry.value;

      final originalFileName = p.basename(stagedFile.path);
      final uniqueFileName = _generateUniqueFileName(destDir, originalFileName);
      final destFile = File(p.join(destDir.path, uniqueFileName));

      await stagedFile.copy(destFile.path);
      newlyCreatedDestFiles.add(destFile);

      finalReceiptPathsMap[key] = destFile.path;
      finalReceiptPathsMap[originalFileName] = destFile.path;
      finalReceiptPathsMap['receipts/$originalFileName'] = destFile.path;
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
          newReceiptPath = finalReceiptPathsMap[normRel] ??
              finalReceiptPathsMap[baseName] ??
              finalReceiptPathsMap[relPath];
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
      'Restored ${projectsJson.length} projects, ${transactionsJson.length} transactions, and ${newlyCreatedDestFiles.length} receipt images successfully.',
    );
  } catch (e) {
    // Compensating cleanup: Delete any newly created destination files
    for (final file in newlyCreatedDestFiles) {
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    return BackupResult(false, 'Restore failed: $e');
  } finally {
    if (stagingDir != null && stagingDir.existsSync()) {
      try {
        await stagingDir.delete(recursive: true);
      } catch (_) {}
    }
  }
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

  try {
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
  } catch (e) {
    return BackupResult(false, 'Restore failed: $e');
  }
}

BackupResult _validateBackupStructure(Map<String, dynamic> data) {
  if (!data.containsKey('version') || data['version'] == null) {
    return BackupResult(
      false,
      'Validation failed: Missing version in backup data.',
    );
  }

  final version = data['version'];
  if (version is! int || version < 1) {
    return BackupResult(
      false,
      'Validation failed: Invalid backup version ($version).',
    );
  }

  if (version > kMaxSupportedVersion) {
    return BackupResult(
      false,
      'Validation failed: Unsupported backup version ($version). Please update the app to restore this backup.',
    );
  }

  if (!data.containsKey('projects') || data['projects'] is! List) {
    return BackupResult(
      false,
      'Validation failed: Missing or invalid projects list.',
    );
  }

  if (!data.containsKey('transactions') || data['transactions'] is! List) {
    return BackupResult(
      false,
      'Validation failed: Missing or invalid transactions list.',
    );
  }

  final projects = data['projects'] as List;
  final projectIds = <int>{};

  for (final pRecord in projects) {
    if (pRecord is! Map<String, dynamic>) {
      return BackupResult(
        false,
        'Validation failed: Corrupted project record structure.',
      );
    }
    final id = pRecord['id'];
    final name = pRecord['name'];
    final createdAt = pRecord['createdAt'];

    if (id is! int || id <= 0) {
      return BackupResult(
        false,
        'Validation failed: Project ID must be a positive integer.',
      );
    }

    if (projectIds.contains(id)) {
      return BackupResult(
        false,
        'Validation failed: Duplicate project ID found in backup (ID: $id).',
      );
    }

    if (name is! String || name.trim().isEmpty) {
      return BackupResult(
        false,
        'Validation failed: Project name cannot be empty.',
      );
    }

    if (createdAt is! String) {
      return BackupResult(
        false,
        'Validation failed: Missing project creation date.',
      );
    }

    try {
      DateTime.parse(createdAt);
    } catch (_) {
      return BackupResult(
        false,
        'Validation failed: Invalid project creation date format.',
      );
    }

    projectIds.add(id);
  }

  final transactions = data['transactions'] as List;
  final transactionIds = <int>{};

  for (final t in transactions) {
    if (t is! Map<String, dynamic>) {
      return BackupResult(
        false,
        'Validation failed: Corrupted transaction record structure.',
      );
    }

    final id = t['id'];
    final amount = t['amount'];
    final type = t['type'];
    final projectId = t['projectId'];
    final date = t['date'];

    if (id is! int || id <= 0) {
      return BackupResult(
        false,
        'Validation failed: Transaction ID must be a positive integer.',
      );
    }

    if (transactionIds.contains(id)) {
      return BackupResult(
        false,
        'Validation failed: Duplicate transaction ID found in backup (ID: $id).',
      );
    }

    if (amount is! num || amount < 0 || !amount.toDouble().isFinite) {
      return BackupResult(
        false,
        'Validation failed: Transaction amount must be a non-negative finite number.',
      );
    }

    if (type is! String || (type != 'income' && type != 'expense')) {
      return BackupResult(
        false,
        'Validation failed: Transaction type must be "income" or "expense".',
      );
    }

    if (projectId is! int || projectId <= 0) {
      return BackupResult(
        false,
        'Validation failed: Invalid project reference in transaction.',
      );
    }

    if (!projectIds.contains(projectId)) {
      return BackupResult(
        false,
        'Validation failed: Transaction references non-existent project (ID: $projectId).',
      );
    }

    if (date is! String) {
      return BackupResult(
        false,
        'Validation failed: Missing transaction date.',
      );
    }

    try {
      DateTime.parse(date);
    } catch (_) {
      return BackupResult(
        false,
        'Validation failed: Invalid transaction date format.',
      );
    }

    transactionIds.add(id);
  }

  return BackupResult(true, 'Validation successful.');
}

String _generateUniqueFileName(Directory dir, String originalFileName) {
  final nameWithoutExt = p.basenameWithoutExtension(originalFileName);
  final ext = p.extension(originalFileName);

  var candidateName = originalFileName;
  var counter = 1;

  while (File(p.join(dir.path, candidateName)).existsSync()) {
    candidateName = '${nameWithoutExt}_restored_$counter$ext';
    counter++;
  }
  return candidateName;
}

Future<Directory> _safeGetApplicationDocumentsDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (_) {
    return Directory.systemTemp;
  }
}

Future<Directory> _safeGetTemporaryDirectory() async {
  try {
    return await getTemporaryDirectory();
  } catch (_) {
    return Directory.systemTemp;
  }
}
