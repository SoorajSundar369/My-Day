import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../widgets/task_tile.dart';
import 'task_editor.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<DataStore>().tasks;
    List<Task> on(DateTime d) =>
        tasks.where((t) => t.due != null && isSameDay(t.due, d)).toList()
          ..sort((a, b) => a.due!.compareTo(b.due!));
    final day = on(_selected);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task on this day',
        onPressed: () => showTaskEditor(context, null, _selected),
        child: const Icon(Icons.add),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: TableCalendar<Task>(
            firstDay: DateTime(2020),
            lastDay: DateTime(2100),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            eventLoader: on,
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Month'},
            onDaySelected: (s, f) => setState(() {
              _selected = s;
              _focused = f;
            }),
            onPageChanged: (f) => _focused = f,
          ),
        ),
        const SizedBox(height: 12),
        if (day.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No tasks on this day.'))),
        for (final t in day)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: TaskTile(t)),
        const SizedBox(height: 72),
      ]),
    );
  }
}
