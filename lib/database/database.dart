import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// ---------- TABLES ----------

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'income' or 'expense'
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
}

class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  TextColumn get type => text()(); // 'income' or 'expense'
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get projectId => integer().references(Projects, #id)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get receiptImagePath => text().nullable()();
}

class Staff extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get position => text().nullable()();
  RealColumn get wage => real().nullable()();
  TextColumn get notes => text().nullable()();
}

class StaffPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get staffId => integer().references(Staff, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();
}

// ---------- DATABASE ----------

@DriftDatabase(tables: [
  Categories,
  Projects,
  Transactions,
  Staff,
  StaffPayments,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'cashbook_db');
}