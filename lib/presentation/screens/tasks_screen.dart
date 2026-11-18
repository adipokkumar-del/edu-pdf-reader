import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/task_model.dart';
import '../../providers/tasks_provider.dart';
import '../widgets/empty_state.dart';
import 'task_editor_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _edit([TaskModel? task]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskEditorScreen(task: task)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TasksProvider>();
    final all = provider.tasks;
    final ordered = provider.ordered;

    final notes = all.where((t) => t.items.isEmpty).length;
    final lists = all.where((t) => t.items.isNotEmpty).length;
    final reminders =
        all.where((t) => !t.completed && t.remindAt != null).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Notes & Checklists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        backgroundColor: AppColors.brown,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: ordered.isEmpty
          ? const EmptyState(
              icon: Icons.checklist_rounded,
              title: 'Nothing here yet',
              message:
                  'Jot down a note, build a checklist, and set a reminder or alarm.',
            )
          : Scrollbar(
              controller: _scroll,
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: ordered.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _Summary(
                      notes: notes,
                      checklists: lists,
                      reminders: reminders,
                    );
                  }
                  final task = ordered[i - 1];
                  return _TaskCard(task: task, onEdit: () => _edit(task));
                },
              ),
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.notes,
    required this.checklists,
    required this.reminders,
  });

  final int notes;
  final int checklists;
  final int reminders;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _Stat(icon: Icons.sticky_note_2_outlined, label: 'Notes', value: notes),
          _Stat(
              icon: Icons.checklist_rounded,
              label: 'Checklists',
              value: checklists),
          _Stat(
              icon: Icons.notifications_active_outlined,
              label: 'Reminders',
              value: reminders),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.brown),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.brownDark,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onEdit});

  final TaskModel task;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TasksProvider>();
    final theme = Theme.of(context);
    final done = task.completed;
    final remindAt = task.remindAt;
    final overdue = !done &&
        remindAt != null &&
        !task.repeatDaily &&
        remindAt.isBefore(DateTime.now());
    final shown = task.items.take(4).toList();
    final strike = done ? TextDecoration.lineThrough : null;
    final muted = done ? AppColors.textSecondary : AppColors.textPrimary;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: strike,
                        color: muted,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    color: Colors.white,
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          onEdit();
                        case 'done':
                          provider.toggleCompleted(task);
                        case 'delete':
                          provider.delete(task.id);
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: const Text('Note deleted'),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => provider.upsert(task),
                                ),
                              ),
                            );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'done',
                        child: Text(done ? 'Mark as not done' : 'Mark as done'),
                      ),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              if (task.title.trim().isNotEmpty && task.body.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10, bottom: 2),
                  child: Text(
                    task.body.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              for (var i = 0; i < shown.length; i++)
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Checkbox(
                        value: shown[i].done,
                        visualDensity: VisualDensity.compact,
                        onChanged: (_) => provider.toggleItem(task, i),
                      ),
                      Expanded(
                        child: Text(
                          shown[i].text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            decoration: shown[i].done || done
                                ? TextDecoration.lineThrough
                                : null,
                            color: shown[i].done || done
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (task.items.length > shown.length)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Text(
                    '+${task.items.length - shown.length} more',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              if (remindAt != null || task.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (remindAt != null)
                        _Chip(
                          icon: task.alarm
                              ? Icons.alarm_rounded
                              : Icons.notifications_outlined,
                          label: formatWhen(remindAt, daily: task.repeatDaily),
                          color: overdue ? Colors.red.shade700 : AppColors.brown,
                        ),
                      if (task.items.isNotEmpty)
                        _Chip(
                          icon: Icons.checklist_rounded,
                          label: '${task.doneCount}/${task.items.length}',
                          color: AppColors.textSecondary,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
