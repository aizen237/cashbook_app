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
    final localPathToZipPath = <String, String>{};

    for (final t in transactions) {
      String? relativeReceiptPath;

      if (t.receiptImagePath != null && t.receiptImagePath!.trim().isNotEmpty) {
        final receiptFile = File(t.receiptImagePath!);
        final canonicalLocalPath = p.canonicalize(receiptFile.path);

        if (!receiptFile.existsSync()) {
          return BackupResult(
            false,
            'Export failed: Transaction ID ${t.id} ("${t.description ?? 'No description'}") references receipt image "${t.receiptImagePath}" which is missing from disk.',
          );
        }

        if (localPathToZipPath.containsKey(canonicalLocalPath)) {
          relativeReceiptPath = localPathToZipPath[canonicalLocalPath];
        } else {
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
          var candidateZipPath = 'receipts/$originalName';
          var counter = 1;
          while (seenZipPaths.contains(candidateZipPath)) {
            final base = p.basenameWithoutExtension(originalName);
            final ext = p.extension(originalName);
            candidateZipPath = 'receipts/${base}_$counter$ext';
            counter++;
          }

          seenZipPaths.add(candidateZipPath);
          localPathToZipPath[canonicalLocalPath] = candidateZipPath;
          relativeReceiptPath = candidateZipPath;
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
  Future<void> Function()? onBeforeDbTransaction,
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
        onBeforeDbTransaction: onBeforeDbTransaction,
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

ArchiveFile? _resolveReceiptEntry(
    String receiptPath, Map<String, ArchiveFile> zipEntriesMap) {
  final norm = p.normalize(receiptPath).replaceAll('\\', '/');

  // 1. Direct exact normalized path match
  if (zipEntriesMap.containsKey(norm)) {
    return zipEntriesMap[norm];
  }

  // 2. Prepend receipts/ if not present
  final withReceipts = norm.startsWith('receipts/') ? norm : 'receipts/$norm';
  if (zipEntriesMap.containsKey(withReceipts)) {
    return zipEntriesMap[withReceipts];
  }

  // 3. Search by basename
  final baseName = p.basename(norm);
  final matches = zipEntriesMap.entries
      .where((e) => p.basename(e.key) == baseName)
      .toList();

  if (matches.length == 1) {
    return matches.first.value;
  } else if (matches.length > 1) {
    throw BackupResult(
      false,
      'Validation failed: Ambiguous receipt reference "$receiptPath" matches multiple entries in ZIP archive.',
    );
  }

  return null;
}

Future<BackupResult> _restoreFromZipArchive(
  AppDatabase db,
  Archive archive, {
  Directory? targetStorageDir,
  Directory? stagingParentDir,
  Future<void> Function()? onBeforeDbTransaction,
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

  // Validate and collect unique referenced receipt images from ZIP
  final referencedEntriesMap = <String, ArchiveFile>{};

  for (final t in transactionsJson) {
    final receiptPath = t['receiptImagePath'] as String?;
    if (receiptPath != null && receiptPath.trim().isNotEmpty) {
      ArchiveFile? entry;
      try {
        entry = _resolveReceiptEntry(receiptPath, zipEntriesMap);
      } catch (e) {
        if (e is BackupResult) return e;
        rethrow;
      }

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

      final normEntryPath = p.normalize(entry.name).replaceAll('\\', '/');
      referencedEntriesMap[normEntryPath] = entry;
    }
  }

  // Stage receipts in a temporary staging directory first
  Directory? stagingDir;
  final newlyCreatedDestFiles = <File>[];

  try {
    final stagingParent = stagingParentDir ?? await _safeGetTemporaryDirectory();
    stagingDir = await stagingParent.createTemp('cashbook_restore_staging_');

    final stagedFileMap = <String, File>{};

    for (final entry in referencedEntriesMap.values) {
      if (entry.isFile && (entry.content as List<int>).isNotEmpty) {
        final normEntryPath = p.normalize(entry.name).replaceAll('\\', '/');
        final originalFileName = p.basename(normEntryPath);
        final stagedFile = File(p.join(
            stagingDir.path, '${stagedFileMap.length}_$originalFileName'));
        await stagedFile.writeAsBytes(entry.content as List<int>);
        stagedFileMap[normEntryPath] = stagedFile;
      }
    }

    final destDir =
        targetStorageDir ?? await _safeGetApplicationDocumentsDirectory();
    if (!destDir.existsSync()) {
      await destDir.create(recursive: true);
    }

    // Copy each unique staged receipt to destination with a collision-safe filename
    final finalReceiptPathsMap = <String, String>{};

    for (final entry in stagedFileMap.entries) {
      final normEntryPath = entry.key;
      final stagedFile = entry.value;

      final originalFileName = p.basename(normEntryPath);
      final uniqueFileName = _generateUniqueFileName(destDir, originalFileName);
      final destFile = File(p.join(destDir.path, uniqueFileName));

      await stagedFile.copy(destFile.path);
      newlyCreatedDestFiles.add(destFile);

      finalReceiptPathsMap[normEntryPath] = destFile.path;
    }

    // Test injection hook before executing DB transaction
    if (onBeforeDbTransaction != null) {
      await onBeforeDbTransaction();
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
          final entry = _resolveReceiptEntry(relPath, zipEntriesMap);
          if (entry != null) {
            final normEntryPath = p.normalize(entry.name).replaceAll('\\', '/');
            newReceiptPath = finalReceiptPathsMap[normEntryPath];
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
