import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:cashbook_app/database/database.dart';
import 'package:cashbook_app/utils/backup_restore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_restore_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('1. Successful ZIP backup & restore cycle (projects, transactions, receipts)', () async {
    final db1 = AppDatabase(NativeDatabase.memory());

    // Create receipt file for DB1
    final storageDir1 = Directory(p.join(tempDir.path, 'storage_db1'))..createSync();
    final receiptFile1 = File(p.join(storageDir1.path, 'receipt_1.jpg'))
      ..writeAsBytesSync([10, 20, 30, 40, 50]);

    // Populate DB1
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

    // Export backup
    final exportDir = Directory(p.join(tempDir.path, 'export_dir'))..createSync();
    final exportResult = await exportBackup(db1, targetDir: exportDir, shareAfterExport: false);

    expect(exportResult.success, isTrue);
    expect(exportResult.filePath, isNotNull);

    final backupZip = File(exportResult.filePath!);
    expect(backupZip.existsSync(), isTrue);

    // Restore into DB2 with different storage directory
    final db2 = AppDatabase(NativeDatabase.memory());
    final storageDir2 = Directory(p.join(tempDir.path, 'storage_db2'))..createSync();

    final restoreResult = await restoreBackup(
      db2,
      backupFile: backupZip,
      targetStorageDir: storageDir2,
    );

    expect(restoreResult.success, isTrue);

    // Verify DB2 content
    final restoredProjects = await db2.select(db2.projects).get();
    expect(restoredProjects.length, equals(1));
    expect(restoredProjects.first.name, equals('Test Project'));

    final restoredTransactions = await db2.select(db2.transactions).get();
    expect(restoredTransactions.length, equals(1));
    final restoredTx = restoredTransactions.first;
    expect(restoredTx.amount, equals(2500.0));
    expect(restoredTx.type, equals('income'));
    expect(restoredTx.receiptImagePath, isNotNull);

    // Verify receipt image was extracted to new storage path
    final restoredReceiptFile = File(restoredTx.receiptImagePath!);
    expect(restoredReceiptFile.existsSync(), isTrue);
    expect(p.dirname(restoredReceiptFile.path), equals(storageDir2.path));
    expect(restoredReceiptFile.readAsBytesSync(), equals([10, 20, 30, 40, 50]));

    await db1.close();
    await db2.close();
  });

  test('2. Restoration on a completely different device directory path', () async {
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

    // Simulate Device B with a totally different filesystem layout
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

  test('3. Corrupted ZIP / invalid backup structure validation rolls back safely', () async {
    final db = AppDatabase(NativeDatabase.memory());

    // Initial safe data in DB
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

    // Create a corrupted zip file with invalid backup.json
    final badJsonData = {
      'version': 1,
      'projects': [
        {'id': 'INVALID_ID_FORMAT', 'name': ''}
      ],
      'transactions': [],
    };
    final jsonBytes = utf8.encode(jsonEncode(badJsonData));

    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    final zipBytes = ZipEncoder().encode(archive);

    final corruptedZip = File(p.join(tempDir.path, 'corrupted.zip'))
      ..writeAsBytesSync(zipBytes);

    final restoreRes = await restoreBackup(db, backupFile: corruptedZip);

    expect(restoreRes.success, isFalse);
    expect(restoreRes.message, contains('Validation failed'));

    // Verify existing database records remain untouched!
    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Existing Project'));

    final transactions = await db.select(db.transactions).get();
    expect(transactions.length, equals(1));
    expect(transactions.first.amount, equals(100.0));

    await db.close();
  });

  test('4. Missing receipt file in ZIP archive validation failure', () async {
    final db = AppDatabase(NativeDatabase.memory());

    // Initial database state
    await db.into(db.projects).insert(
          ProjectsCompanion.insert(name: 'Safety Check Project'),
        );

    // Create zip claiming receipt_99.png exists, but NOT including receipt_99.png in ZIP
    final jsonBackup = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'projects': [
        {'id': 1, 'name': 'Project 1', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [
        {
          'id': 10,
          'amount': 500.0,
          'type': 'expense',
          'projectId': 1,
          'date': DateTime.now().toIso8601String(),
          'receiptImagePath': 'receipts/receipt_99.png',
        }
      ],
    };

    final jsonBytes = utf8.encode(jsonEncode(jsonBackup));
    final archive = Archive();
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
    final zipBytes = ZipEncoder().encode(archive);

    final missingReceiptZip = File(p.join(tempDir.path, 'missing_receipt.zip'))
      ..writeAsBytesSync(zipBytes);

    final restoreRes = await restoreBackup(db, backupFile: missingReceiptZip);

    expect(restoreRes.success, isFalse);
    expect(restoreRes.message, contains('missing from the ZIP backup archive'));

    // Verify existing data preserved
    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Safety Check Project'));

    await db.close();
  });

  test('5. Legacy JSON backup compatibility test', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final legacyJsonData = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'projects': [
        {'id': 1, 'name': 'Legacy Project', 'createdAt': DateTime.now().toIso8601String()}
      ],
      'transactions': [
        {
          'id': 1,
          'amount': 300.0,
          'type': 'income',
          'projectId': 1,
          'date': DateTime.now().toIso8601String(),
          'description': 'Legacy item',
          'receiptImagePath': '/non_existent_device_path/image.jpg',
        }
      ],
    };

    final jsonFile = File(p.join(tempDir.path, 'legacy_backup.json'))
      ..writeAsStringSync(jsonEncode(legacyJsonData));

    final restoreRes = await restoreBackup(db, backupFile: jsonFile);

    expect(restoreRes.success, isTrue);
    expect(restoreRes.message, contains('legacy JSON backup'));
    expect(restoreRes.message, contains('Receipt images cannot be recovered'));

    final projects = await db.select(db.projects).get();
    expect(projects.length, equals(1));
    expect(projects.first.name, equals('Legacy Project'));

    final transactions = await db.select(db.transactions).get();
    expect(transactions.length, equals(1));
    expect(transactions.first.amount, equals(300.0));
    // Non-existent image path is set to null safely
    expect(transactions.first.receiptImagePath, isNull);

    await db.close();
  });
}
