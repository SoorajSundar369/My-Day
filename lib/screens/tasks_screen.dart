import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../widgets/fx.dart';
import '../widgets/task_tile.dart';
import 'task_editor.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _filter = 'Open';
  static const _filters = ['Open', 'Today', 'Upcoming', 'Overdue', 'Done', 'All'];

  bool _match(Task t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    switch (_filter) {
      case 'Open':
        return !t.done;
      case 'Today':
        return !t.done && t.due != null && !t.due!.isBefore(today) && t.due!.isBefore(tomorrow);
      case 'Upcoming':
        return !t.done && t.due != null && !t.due!.isBefore(tomorrow);
      case 'Overdue':
        return !t.done && t.due != null && t.due!.isBefore(now);
      case 'Done':
        return t.done;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<DataStore>().tasks.where(_match).toList()
      ..sort((a, b) {
        if (a.due == null && b.due == null) return b.priority.compareTo(a.priority);
        if (a.due == null) return 1;
        if (b.due == null) return -1;
        return a.due!.compareTo(b.due!);
      });
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTaskEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(f),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f)),
                ),
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? const Center(child: Text('Nothing here.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => Reveal(index: i, child: TaskTile(tasks[i])),
                ),
        ),
      ]),
    );
  }
}
