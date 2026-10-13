import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../data/data_store.dart';
import '../data/models.dart';

Future<void> showTaskEditor(BuildContext context, [Task? task, DateTime? presetDay]) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: _TaskForm(task: task, presetDay: presetDay),
      ),
    ),
  );
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.task, this.presetDay});
  final Task? task;
  final DateTime? presetDay;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _tags;
  final _newItem = TextEditingController();
  DateTime? _due;
  int _priority = 1;
  String _repeat = 'none';
  bool _remind = false;
  late List<ChecklistItem> _items;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _desc = TextEditingController(text: t?.description ?? '');
    _tags = TextEditingController(text: t?.tags.join(', ') ?? '');
    _due = t?.due ??
        (widget.presetDay == null
            ? null
            : DateTime(widget.presetDay!.year, widget.presetDay!.month, widget.presetDay!.day, 9));
    _priority = t?.priority ?? 1;
    _repeat = t?.repeat ?? 'none';
    _remind = t?.remind ?? false;
    _items = (t?.checklist ?? []).map((e) => ChecklistItem(e.text, e.done)).toList();
  }

  Future<void> _pickDue() async {
    final base = _due ?? DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final store = context.read<DataStore>();
    final task = widget.task ?? Task(id: const Uuid().v4(), title: '');
    final dueChanged = task.due != _due;
    task
      ..title = _title.text.trim()
      ..description = _desc.text.trim()
      ..due = _due
      ..priority = _priority
      ..repeat = _due == null ? 'none' : _repeat
      ..remind = _due != null && _remind
      ..tags = _tags.text
          .split(',')
          .map((e) => e.trim().replaceAll('#', ''))
          .where((e) => e.isNotEmpty)
          .toList()
      ..checklist = _items;
    if (dueChanged) task.notified = false;
    await store.saveTask(task);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.task != null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(editing ? 'Edit task' : 'New task'),
        backgroundColor: Colors.transparent,
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await context.read<DataStore>().deleteTask(widget.task!);
                if (mounted) Navigator.pop(context);
              },
            ),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Details')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_due == null ? 'Set due date & time' : DateFormat('EEE, d MMM  h:mm a').format(_due!)),
              onPressed: _pickDue,
            ),
          ),
          if (_due != null)
            IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _due = null)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Low')),
                DropdownMenuItem(value: 1, child: Text('Normal')),
                DropdownMenuItem(value: 2, child: Text('High')),
              ],
              onChanged: (v) => setState(() => _priority = v!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Never')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: _due == null ? null : (v) => setState(() => _repeat = v!),
            ),
          ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notify me at the due time'),
          subtitle: _due == null ? const Text('Set a due date first') : null,
          value: _remind && _due != null,
          onChanged: _due == null ? null : (v) => setState(() => _remind = v),
        ),
        TextField(
            controller: _tags,
            decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
        const SizedBox(height: 16),
        Text('Checklist', style: Theme.of(context).textTheme.titleSmall),
        for (var i = 0; i < _items.length; i++)
          Row(children: [
            Checkbox(
                value: _items[i].done,
                onChanged: (v) => setState(() => _items[i].done = v ?? false)),
            Expanded(child: Text(_items[i].text)),
            IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _items.removeAt(i))),
          ]),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _newItem,
              decoration: const InputDecoration(hintText: 'Add checklist item'),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          IconButton(icon: const Icon(Icons.add), onPressed: _addItem),
        ]),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _title.text.trim().isEmpty ? null : _save, child: const Text('Save')),
      ]),
    );
  }

  void _addItem() {
    final t = _newItem.text.trim();
    if (t.isEmpty) return;
    setState(() => _items.add(ChecklistItem(t)));
    _newItem.clear();
  }
}
