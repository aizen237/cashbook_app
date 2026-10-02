import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import 'database_provider.dart';

final projectsProvider = StreamProvider<List<Project>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.projects)..orderBy([(p) => OrderingTerm.desc(p.id)]))
      .watch();
});

final projectProvider = StreamProvider.family<Project?, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.projects)..where((p) => p.id.equals(id)))
      .watchSingleOrNull();
});

class ProjectTotals {
  final double income;
  final double expense;
  double get balance => income - expense;

  ProjectTotals({required this.income, required this.expense});
}

final projectTotalsProvider =
StreamProvider.family<ProjectTotals, int>((ref, projectId) {
  final db = ref.watch(databaseProvider);

  final query = db.select(db.transactions)
    ..where((t) => t.projectId.equals(projectId));

  return query.watch().map((transactions) {
    double income = 0;
    double expense = 0;
    for (final t in transactions) {
      if (t.type == 'income') {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }
    return ProjectTotals(income: income, expense: expense);
  });
});

final projectActionsProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return ProjectActions(db);
});

class ProjectActions {
  final AppDatabase db;
  ProjectActions(this.db);

  Future<void> addProject(String name) async {
    await db.into(db.projects).insert(
      ProjectsCompanion.insert(name: name),
    );
  }

  Future<void> updateProject(int id, String newName) async {
    await (db.update(db.projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(name: Value(newName)),
    );
  }

  Future<void> deleteProject(int id) async {
    await (db.delete(db.projects)..where((p) => p.id.equals(id))).go();
  }
}