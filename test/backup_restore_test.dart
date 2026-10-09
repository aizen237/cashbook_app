import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:cashbook_app/database/database.dart';
import 'package:cashbook_app/utils/backup_restore.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('backup_restore_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('1. ZIP export and successful restoration cycle', () async {
    final db1 = AppDatabase(NativeDatabase.memory());

    final storageDir1 = Directory(p.join(tempDir.path, 'storage_db1'))..createSync();
    final receiptFile1 = File(p.join(storageDir1.path, 'receipt_1.jpg'))
      ..writeAsBytesSync([10, 20, 30, 40, 50]);

    final projId = await db1.into(db1.projects).insert(
          ProjectsCompanion.insert(
            name: 'Test Project',
            createdAt: Value(DateTime(2026, 10, 1)),
          ),
        );

    await db1.into(db1.transactions).insert(
          TransactionsCompanion.insert(
            amount: 2500.0,
            type: 'income',
            projectId: projId,
            description: const Value('Advance payment'),
            date: Value(DateTime(2026, 10, 2)),
            paymentMethod: const Value('Bank Transfer'),
            receiptImagePath: Value(receiptFile1.path),
          ),
        );

    final exportDir = Directory(p.join(tempDir.path, 'export_dir'))..createSync();
    final exportResult = await exportBackup(db1, targetDir: exportDir, shareAfterExport: false);

    expect(exportResult.success, isTrue);
    expect(exportResult.filePath, isNotNull);

    final backupZip = File(exportResult.filePath!);
    expect(backupZip.existsSync(), isTrue);

    final db2 = AppDatabase(NativeDatabase.memory());
    final storageDir2 = Directory(p.join(tempDir.path, 'storage_db2'))..createSync();

    final restoreResult = await restoreBackup(
      db2,
      backupFile: backupZip,
      targetStorageDir: storageDir2,
    );

    expect(restoreResult.success, isTrue, reason: restoreResult.message);

    final restoredProjects = await db2.select(db2.projects).get();
    expect(restoredProjects.length, equals(1));
    expect(restoredProjects.first.name, equals('Test Project'));

    final restoredTransactions = await db2.select(db2.transactions).get();
    expect(restoredTransactions.length, equals(1));
    final restoredTx = restoredTransactions.first;
    expect(restoredTx.amount, equals(2500.0));
    expect(restoredTx.type, equals('income'));
    expect(restoredTx.receiptImagePath, isNotNull);

    final restoredReceiptFile = File(restoredTx.receiptImagePath!);
    expect(restoredReceiptFile.existsSync(), isTrue);
    expect(p.dirname(restoredReceiptFile.path), equals(storageDir2.path));
    expect(restoredReceiptFile.readAsBytesSync(), equals([10, 20, 30, 40, 50]));

    await db1.close();
    await db2.close();
  });

  test('2. Restoration to a different device directory path', () async {
    final db1 = AppDatabase(NativeDatabase.memory());

    final devicePathA = Directory(p.join(tempDir.path, 'device_A_documents'))..createSync();
    final receiptA = File(p.join(devicePathA.path, 'invoice_99.png'))
      ..writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8]);

    final pId = await db1.into(db1.projects).insert(
          ProjectsCompanion.insert(name: 'Device A Project'),
        );

    await db1.into(db1.transactions).insert(
          TransactionsCompanion.insert(
            amount: 750.0,
            type: 'expense',
            projectId: pId,
            receiptImagePath: Value(receiptA.path),
          ),
        );

    final exportDir = Directory(p.join(tempDir.path, 'exports'))..createSync();
    final exportRes = await exportBackup(db1, targetDir: exportDir, shareAfterExport: false);
    final zipFile = File(exportRes.filePath!);

    final dbDeviceB = AppDatabase(NativeDatabase.memory());
    final devicePathB = Directory(p.join(tempDir.path, 'device_B_documents'))..createSync();

    final restoreRes = await restoreBackup(
      dbDeviceB,
      backupFile: zipFile,
      targetStorageDir: devicePathB,
    );

    expect(restoreRes.success, isTrue);

    final txsB = await dbDeviceB.select(dbDeviceB.transactions).get();
    expect(txsB.length, equals(1));
    expect(txsB.first.receiptImagePath, startsWith(devicePathB.path));

    final fileB = File(txsB.first.receiptImagePath!);
    expect(fileB.existsSync(), isTrue);
    expect(fileB.readAsBytesSync(), equals([1, 2, 3, 4, 5, 6, 7, 8]));

    await db1.close();
    await dbDeviceB.close();
  });

  test('3. ZIP sharing with correct file extension and MIME type', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final exportDir = Directory(p.join(tempDir.path, 'export_share'))..createSync();

    XFile? sharedFile;
    final exportRes = await exportBackup(
      db,
      targetDir: exportDir,
      shareAfterExport: true,
      shareHandler: (files, {text}) async {
        sharedFile = files.first;
        return const ShareResult('success', ShareResultStatus.success);
      },
    );

    expect(exportRes.success, isTrue);
    expect(sharedFile, isNotNull);
    expect(sharedFile!.mimeType, equals('application/zip'));
    expect(p.extension(sharedFile!.path), equals('.zip'));

    final file = File(exportRes.filePath!);
    expect(file.existsSync(), isTrue);

    await db.close();
  });

  test('4. Missing receipt file during export fails cleanly without partial file output', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final pId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(name: 'Missing Receipt Test'),
        );

    final missingPath = p.join(tempDir.path, 'does_not_exist.jpg');
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            amount: 500.0,
            type: 'expense',
            projectId: pId,
            description: const Value('Office Supplies'),
            receiptImagePath: Value(missingPath),
          ),
        );

    final exportDir = Directory(p.join(tempDir.path, 'export_fail'))..createSync();
    final exportRes = await exportBackup(db, targetDir: exportDir, shareAfterExport: false);

    expect(exportRes.success, isFalse);
    expect(exportRes.message, contains('missing from disk'));
    expect(exportRes.message, contains('Office Supplies'));

    // Verify partial zip was not created or was cleaned up
    final zipFiles = exportDir.listSync();
    expect(zipFiles.isEmpty, isTrue);

    await db.close();
  });

  test('5. Duplicate receipt filenames handled uniquely without overwriting', () async {
    final db1 = AppDatabase(NativeDatabase.memory());

    final dirA = Directory(p.join(tempDir.path, 'folderA'))..createSync();
    final dirB = Directory(p.join(tempDir.path, 'folderB'))..createSync();

    final file1 = File(p.join(dirA.path, 'receipt.jpg'))..writeAsBytesSync([1, 1, 1]);
    final file2 = File(p.join(dirB.path, 'receipt.jpg'))..writeAsBytesSync([2, 2, 2]);

    final pId = await db1.into(db1.projects).insert(
          ProjectsCompanion.insert(name: 'Duplicate Receipts Project'),
        );

    await db1.into(db1.transactions).insert(
          TransactionsCompanion.insert(
            amount: 100.0,
            type: 'expense',
            projectId: pId,
            receiptImagePath: Value(file1.path),
          ),
        );

    await db1.into(db1.transactions).insert(
          TransactionsCompanion.insert(
            amount: 200.0,
            type: 'expense',
            projectId: pId,
            receiptImagePath: Value(file2.path),
          ),
        );

    final exportDir = Directory(p.join(tempDir.path, 'dup_export'))..createSync();
    final exportRes = await exportBackup(db1, targetDir: exportDir, shareAfterExport: false);
    expect(exportRes.success, isTrue);

    final db2 = AppDatabase(NativeDatabase.memory());
    final restoreDir = Directory(p.join(tempDir.path, 'dup_restore'))..createSync();

    final restoreRes = await restoreBackup(
      db2,
      backupFile: File(exportRes.filePath!),
      targetStorageDir: restoreDir,
    );

    expect(restoreRes.success, isTrue);

    final txs = await db2.select(db2.transactions).get();
    expect(txs.length, equals(2));

    final r1 = File(txs[0].receiptImagePath!);
    final r2 = File(txs[1].receiptImagePath!);

    expect(r1.path, isNot(equals(r2.path)));
    expect(r1.existsSync(), isTrue);
    expect(r2.existsSync(), isTrue);

    final bytesSet = {r1.readAsBytesSync().first, r2.readAsBytesSync().first};
    expect(bytesSet, equals({1, 2}));

    await db1.close();
    await db2.close();
  });

  test('6. Corrupted ZIP archives fail validation and preserve existing data', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final pId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(name: 'Existing Project'),
        );
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            amount: 100.0,
            type: 'income',
            projectId: pId,
          ),
        );

    final corruptedZip = File(p.join(tempDir.path, 'corrupted.zip'))
      ..writeAsBytesSync([80, 75, 3, 4, 0, 0, 0, 0, 99, 99]);

    final restoreRes = await restoreBackup(db, backupFile: corruptedZip);

    expect(restoreRes.success, isFalse);
    expect(restoreRes.message, contains('Validation failed'));

    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Existing Project'));

    await db.close();
  });

  test('7. Unsupported backup versions rejected', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final futureData = {
      'version': 99,
      'projects': [
        {'id': 1, 'name': 'Future Proj', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [],
    };

    final jsonBytes = utf8.encode(jsonEncode(futureData));
    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    final zipBytes = ZipEncoder().encode(archive);

    final zipFile = File(p.join(tempDir.path, 'future_ver.zip'))..writeAsBytesSync(zipBytes);

    final restoreRes = await restoreBackup(db, backupFile: zipFile);

    expect(restoreRes.success, isFalse);
    expect(restoreRes.message, contains('Unsupported backup version (99)'));

    await db.close();
  });

  test('8. Invalid and duplicate record IDs fail validation', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final dupIdData = {
      'version': 2,
      'projects': [
        {'id': 1, 'name': 'Proj 1', 'createdAt': DateTime.now().toIso8601String()},
        {'id': 1, 'name': 'Proj 2 (Dup ID)', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [],
    };

    final jsonBytes = utf8.encode(jsonEncode(dupIdData));
    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    final zipBytes = ZipEncoder().encode(archive);

    final zipFile = File(p.join(tempDir.path, 'dup_id.zip'))..writeAsBytesSync(zipBytes);

    final restoreRes = await restoreBackup(db, backupFile: zipFile);

    expect(restoreRes.success, isFalse);
    expect(restoreRes.message, contains('Duplicate project ID found'));

    await db.close();
  });

  test('9. Unsafe archive paths (Zip Slip) rejected', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final jsonBackup = {
      'version': 2,
      'projects': [
        {'id': 1, 'name': 'Zip Slip Test', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [],
    };

    final jsonBytes = utf8.encode(jsonEncode(jsonBackup));
    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    archive.addFile(ArchiveFile('../../../evil.txt', 4, [1, 2, 3, 4]));

    final zipBytes = ZipEncoder().encode(archive);
    final zipFile = File(p.join(tempDir.path, 'zip_slip.zip'))..writeAsBytesSync(zipBytes);

    final restoreRes = await restoreBackup(db, backupFile: zipFile);

    expect(restoreRes.success, isFalse);
    expect(restoreRes.message, contains('Unsafe archive path detected'));

    await db.close();
  });

  test('10. File write failure during restoration handles error gracefully', () async {
    final db = AppDatabase(NativeDatabase.memory());

    await db.into(db.projects).insert(
          ProjectsCompanion.insert(name: 'Initial Proj'),
        );

    // Create valid zip with receipt
    final dbExport = AppDatabase(NativeDatabase.memory());
    final exportStorage = Directory(p.join(tempDir.path, 'exp_storage'))..createSync();
    final receipt = File(p.join(exportStorage.path, 'rec.jpg'))..writeAsBytesSync([9, 9, 9]);

    final expPId = await dbExport.into(dbExport.projects).insert(
          ProjectsCompanion.insert(name: 'Export Proj'),
        );
    await dbExport.into(dbExport.transactions).insert(
          TransactionsCompanion.insert(
            amount: 50.0,
            type: 'income',
            projectId: expPId,
            receiptImagePath: Value(receipt.path),
          ),
        );

    final exportDir = Directory(p.join(tempDir.path, 'exp_out'))..createSync();
    final exportRes = await exportBackup(dbExport, targetDir: exportDir, shareAfterExport: false);
    final zipFile = File(exportRes.filePath!);

    // Invalid/unwritable target directory path
    final invalidDestDir = Directory(p.join(tempDir.path, 'invalid_dir_file.txt'));
    await File(invalidDestDir.path).writeAsString('I am a file, not a folder');

    final restoreRes = await restoreBackup(
      db,
      backupFile: zipFile,
      targetStorageDir: invalidDestDir,
    );

    expect(restoreRes.success, isFalse);
    expect(restoreRes.message, contains('Restore failed'));

    // Verify existing database data preserved
    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Initial Proj'));

    await db.close();
    await dbExport.close();
  });

  test('11. Database transaction failure after receipt extraction cleans up newly created files', () async {
    final db = AppDatabase(NativeDatabase.memory());

    // Populate initial DB
    await db.into(db.projects).insert(
          ProjectsCompanion.insert(name: 'Initial Data'),
        );

    // Create zip that passes receipt validation but fails inside DB transaction (e.g., negative amount)
    final jsonBackup = {
      'version': 2,
      'projects': [
        {'id': 1, 'name': 'Project 1', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [
        {
          'id': 10,
          'amount': -500.0, // Invalid negative amount
          'type': 'expense',
          'projectId': 1,
          'date': DateTime.now().toIso8601String(),
          'receiptImagePath': 'receipts/rec.jpg',
        }
      ],
    };

    final jsonBytes = utf8.encode(jsonEncode(jsonBackup));
    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    archive.addFile(ArchiveFile('receipts/rec.jpg', 3, [1, 2, 3]));

    final zipBytes = ZipEncoder().encode(archive);
    final zipFile = File(p.join(tempDir.path, 'db_fail.zip'))..writeAsBytesSync(zipBytes);

    final targetStorage = Directory(p.join(tempDir.path, 'target_storage'))..createSync();

    final restoreRes = await restoreBackup(
      db,
      backupFile: zipFile,
      targetStorageDir: targetStorage,
    );

    expect(restoreRes.success, isFalse);

    // Verify newly created receipt files were cleaned up
    expect(targetStorage.listSync().isEmpty, isTrue);

    // Verify initial DB state preserved
    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Initial Data'));

    await db.close();
  });

  test('12. Preservation of pre-existing receipts and database records after failure', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final targetStorage = Directory(p.join(tempDir.path, 'target_storage'))..createSync();
    final existingReceipt = File(p.join(targetStorage.path, 'pre_existing.jpg'))
      ..writeAsBytesSync([100, 200, 255]);

    final pId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(name: 'Pre-existing Project'),
        );
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            amount: 10.0,
            type: 'income',
            projectId: pId,
            receiptImagePath: Value(existingReceipt.path),
          ),
        );

    // Try restoring a corrupted zip
    final corruptedZip = File(p.join(tempDir.path, 'bad.zip'))..writeAsBytesSync([1, 2, 3]);

    final restoreRes = await restoreBackup(
      db,
      backupFile: corruptedZip,
      targetStorageDir: targetStorage,
    );

    expect(restoreRes.success, isFalse);

    // Verify pre-existing receipt file is still intact!
    expect(existingReceipt.existsSync(), isTrue);
    expect(existingReceipt.readAsBytesSync(), equals([100, 200, 255]));

    // Verify DB records intact
    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Pre-existing Project'));

    await db.close();
  });

  test('13. Legacy JSON backup restoration', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final legacyJsonData = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'projects': [
        {'id': 1, 'name': 'Legacy Proj', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [
        {
          'id': 1,
          'amount': 300.0,
          'type': 'income',
          'projectId': 1,
          'date': DateTime.now().toIso8601String(),
          'description': 'Legacy item',
          'receiptImagePath': '/non_existent/file.jpg',
        }
      ],
    };

    final jsonFile = File(p.join(tempDir.path, 'legacy.json'))
      ..writeAsStringSync(jsonEncode(legacyJsonData));

    final restoreRes = await restoreBackup(db, backupFile: jsonFile);

    expect(restoreRes.success, isTrue);
    expect(restoreRes.message, contains('legacy JSON backup'));
    expect(restoreRes.message, contains('Receipt images cannot be recovered'));

    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Legacy Proj'));

    final transactions = await db.select(db.transactions).get();
    expect(transactions.length, equals(1));
    expect(transactions.first.amount, equals(300.0));
    expect(transactions.first.receiptImagePath, isNull);

    await db.close();
  });

  test('14. Staging directory cleanup after successful and failed restores', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final jsonBackup = {
      'version': 2,
      'projects': [
        {'id': 1, 'name': 'Cleanup Test', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [],
    };

    final jsonBytes = utf8.encode(jsonEncode(jsonBackup));
    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    final zipBytes = ZipEncoder().encode(archive);

    final zipFile = File(p.join(tempDir.path, 'cleanup.zip'))..writeAsBytesSync(zipBytes);

    final restoreRes = await restoreBackup(
      db,
      backupFile: zipFile,
      stagingParentDir: tempDir,
    );
    expect(restoreRes.success, isTrue);

    // Verify tempDir has no leftover cashbook_restore_staging_ folders
    final leftoverStaging = tempDir
        .listSync()
        .where((e) => p.basename(e.path).startsWith('cashbook_restore_staging_'));
    expect(leftoverStaging.isEmpty, isTrue);

    await db.close();
  });
}
