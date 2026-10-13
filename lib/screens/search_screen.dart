import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/helpers.dart';
import '../data/data_store.dart';
import '../data/habit_store.dart';
import '../data/money_store.dart';
import '../widgets/task_tile.dart';
import 'expense_editor.dart';
import 'files_screen.dart';
import 'habit_detail.dart';
import 'notes_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _q = '';

  bool _has(String text) => text.toLowerCase().contains(_q);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DataStore>();
    final habitStore = context.watch<HabitStore>();
    final money = context.watch<MoneyStore>();
    final habits = _q.isEmpty
        ? []
        : habitStore.habits.where((h) => _has('${h.name} ${h.note}')).toList();
    final entries = _q.isEmpty
        ? []
        : money.expenses
            .where((e) => _has('${e.note} ${money.labelOf(e)} ${e.method} ${e.amount}'))
            .take(30)
            .toList();
    final tasks = _q.isEmpty
        ? []
        : store.tasks.where((t) => _has('${t.title} ${t.description} ${t.tags.join(' ')}')).toList();
    final notes = _q.isEmpty
        ? []
        : store.notes.where((n) => _has('${n.title} ${n.body} ${n.tags.join(' ')}')).toList();
    final files = _q.isEmpty
        ? []
        : store.visibleFiles.where((f) => _has('${f.name} ${f.folder} ${f.tags.join(' ')}')).toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Search tasks, notes, files…',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
      ),
      body: _q.isEmpty
          ? const Center(child: Text('Type to search everything.'))
          : (tasks.isEmpty && notes.isEmpty && files.isEmpty && habits.isEmpty && entries.isEmpty)
              ? const Center(child: Text('No results.'))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  if (tasks.isNotEmpty) const Text('Tasks'),
                  for (final t in tasks)
                    Padding(padding: const EdgeInsets.only(top: 6), child: TaskTile(t)),
                  if (notes.isNotEmpty)
                    const Padding(padding: EdgeInsets.only(top: 16, bottom: 6), child: Text('Notes')),
                  for (final n in notes)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.sticky_note_2_outlined),
                        title: Text(n.title.isEmpty ? 'Untitled' : n.title),
                        subtitle: Text(n.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => openNote(context, n),
                      ),
                    ),
                  if (habits.isNotEmpty)
                    const Padding(padding: EdgeInsets.only(top: 16, bottom: 6), child: Text('Habits')),
                  for (final h in habits)
                    Card(
                      child: ListTile(
                        leading: habitGlyph(h, palette[h.color % palette.length]),
                        title: Text(h.name),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: h.id))),
                      ),
                    ),
                  if (entries.isNotEmpty)
                    const Padding(padding: EdgeInsets.only(top: 16, bottom: 6), child: Text('Money')),
                  for (final e in entries)
                    Card(
                      child: ListTile(
                        leading: Icon(moneyIcons[(money.cat(e.category)?.icon ?? 6) % moneyIcons.length]),
                        title: Text('${e.isIncome ? '+' : '-'}${money.fmt(e.amount)} · ${money.labelOf(e)}'),
                        subtitle: Text('${dayKey(e.date)}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
                        onTap: () => showExpenseEditor(context, e),
                      ),
                    ),
                  if (files.isNotEmpty)
                    const Padding(padding: EdgeInsets.only(top: 16, bottom: 6), child: Text('Files')),
                  for (final f in files)
                    Card(
                      child: ListTile(
                        leading: Icon(fileIcon(f)),
                        title: Text(f.name),
                        subtitle: Text(fmtSize(f.size)),
                        onTap: () => openVaultFile(context, f),
                      ),
                    ),
                ]),
    );
  }
}
