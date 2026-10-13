import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../screens/task_editor.dart';
import 'fx.dart';

Color priorityColor(int p) => switch (p) {
      2 => Colors.redAccent,
      0 => Colors.blueGrey,
      _ => Colors.orange,
    };

String fmtDue(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final time = DateFormat.jm().format(d);
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Tomorrow $time';
  if (diff == -1) return 'Yesterday $time';
  return '${DateFormat('d MMM').format(d)} $time';
}

class TaskTile extends StatelessWidget {
  const TaskTile(this.task, {super.key});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final store = context.read<DataStore>();
    final overdue = task.due != null && !task.done && task.due!.isBefore(DateTime.now());
    final cs = Theme.of(context).colorScheme;
    final doneCount = task.checklist.where((c) => c.done).length;
    return Card(
      child: ListTile(
        leading: Builder(
          builder: (c) => Checkbox(
            value: task.done,
            onChanged: (_) {
              final completing = !task.done;
              store.toggleDone(task);
              if (completing) celebrate(c);
            },
          ),
        ),
        title: Text(task.title,
            style: task.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (task.due != null)
            Text(fmtDue(task.due!), style: TextStyle(color: overdue ? cs.error : null)),
          if (task.remind) const Icon(Icons.notifications_active_outlined, size: 14),
          if (task.repeat != 'none') const Icon(Icons.repeat, size: 14),
          if (task.checklist.isNotEmpty) Text('$doneCount/${task.checklist.length}'),
          for (final t in task.tags) Text('#$t', style: TextStyle(color: cs.primary)),
        ]),
        trailing: Icon(Icons.flag, color: priorityColor(task.priority), size: 20),
        onTap: () => showTaskEditor(context, task),
      ),
    );
  }
}
