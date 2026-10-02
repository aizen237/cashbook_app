import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../providers/project_provider.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  Future<void> _addProjectDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project name',
            hintText: 'e.g. Residential House',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await ref.read(projectActionsProvider).addProject(name);
    }
  }

  Future<void> _editProjectDialog(
      BuildContext context, WidgetRef ref, Project project) async {
    final controller = TextEditingController(text: project.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project name',
            hintText: 'e.g. Residential House',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != project.name) {
      await ref
          .read(projectActionsProvider)
          .updateProject(project.id, newName);
    }
  }

  Future<void> _confirmDeleteProject(
      BuildContext context, WidgetRef ref, Project project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete project?'),
        content: const Text(
          'Transactions linked to this project will keep their data but lose the project link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(projectActionsProvider).deleteProject(project.id);
    }
  }

  void _showProjectOptions(
      BuildContext context, WidgetRef ref, Project project) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Project'),
              onTap: () {
                Navigator.pop(context);
                _editProjectDialog(context, ref, project);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Project',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteProject(context, ref, project);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addProjectDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) {
            return const Center(child: Text('No projects yet'));
          }

          return ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              final totalsAsync =
              ref.watch(projectTotalsProvider(project.id));

              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(
                    project.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: totalsAsync.when(
                    data: (totals) => Text(
                      'Income: ETB ${totals.income.toStringAsFixed(2)}  •  '
                          'Expense: ETB ${totals.expense.toStringAsFixed(2)}',
                    ),
                    loading: () => const Text('Loading...'),
                    error: (e, _) => Text('Error: $e'),
                  ),
                  trailing: totalsAsync.when(
                    data: (totals) => Text(
                      'ETB ${totals.balance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: totals.balance >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => const Icon(Icons.error),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProjectDetailScreen(project: project),
                      ),
                    );
                  },
                  onLongPress: () =>
                      _showProjectOptions(context, ref, project),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}