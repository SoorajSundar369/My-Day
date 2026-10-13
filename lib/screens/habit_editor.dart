import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/helpers.dart';
import '../data/habit_models.dart';
import '../data/habit_store.dart';

Future<void> showHabitEditor(BuildContext context, [Habit? habit]) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: HabitForm(habit: habit),
      ),
    ),
  );
}

class HabitForm extends StatefulWidget {
  const HabitForm({super.key, this.habit, this.onDone});

  /// Called instead of closing a dialog (used by the home-screen quick add).
  final VoidCallback? onDone;
  final Habit? habit;

  @override
  State<HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<HabitForm> {
  void _close() => widget.onDone != null ? widget.onDone!() : Navigator.pop(context);

  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late final _note = TextEditingController(text: widget.habit?.note ?? '');
  late final _unit = TextEditingController(text: widget.habit?.unit ?? '');
  late final _target = TextEditingController(text: '${widget.habit?.target ?? 1}');
  late int _icon = widget.habit?.icon ?? 0;
  late int _color = widget.habit?.color ?? 0;
  late String _type = widget.habit?.type ?? 'check';
  late String _freq = widget.habit?.freq ?? 'daily';
  late int _weekdays = widget.habit?.weekdays ?? 127;
  late int _times = widget.habit?.timesPerWeek ?? 3;
  late String? _remind = widget.habit?.remindTime;

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Future<void> _pickTime() async {
    final p = _remind?.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: p == null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    if (t != null) {
      setState(() => _remind =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    final store = context.read<HabitStore>();
    final h = widget.habit ?? Habit(id: const Uuid().v4(), name: '');
    h
      ..name = _name.text.trim()
      ..note = _note.text.trim()
      ..icon = _icon
      ..color = _color
      ..type = _type
      ..target = _type == 'count' ? (int.tryParse(_target.text) ?? 1).clamp(1, 100000) : 1
      ..unit = _type == 'count' ? _unit.text.trim() : ''
      ..freq = _freq
      ..weekdays = _weekdays == 0 ? 127 : _weekdays
      ..timesPerWeek = _times
      ..remindTime = _remind;
    await store.save(h);
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Text(widget.habit == null ? 'New habit' : 'Edit habit'),
        actions: [IconButton(icon: const Icon(Icons.close), onPressed: _close)],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Habit name (e.g. Read 20 pages)'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        Text('Icon', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _icon = -1),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _icon == -1 ? palette[_color].withValues(alpha: 0.2) : null,
                border: Border.all(color: _icon == -1 ? palette[_color] : cs.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('No icon',
                  style: TextStyle(fontSize: 12, color: _icon == -1 ? palette[_color] : null)),
            ),
          ),
          for (var i = 0; i < habitIcons.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _icon = i),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _icon == i ? palette[_color].withValues(alpha: 0.2) : null,
                  border: Border.all(color: _icon == i ? palette[_color] : cs.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(habitIcons[i], size: 22, color: _icon == i ? palette[_color] : null),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Text('Colour', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < palette.length; i++)
            GestureDetector(
              onTap: () => setState(() => _color = i),
              child: CircleAvatar(
                  radius: 15,
                  backgroundColor: palette[i],
                  child: _color == i ? const Icon(Icons.check, color: Colors.white, size: 16) : null),
            ),
        ]),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'check', icon: Icon(Icons.check), label: Text('Yes / No')),
            ButtonSegment(value: 'count', icon: Icon(Icons.numbers), label: Text('Counted')),
          ],
          selected: {_type},
          onSelectionChanged: (v) => setState(() => _type = v.first),
        ),
        if (_type == 'count') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                  controller: _target,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Daily target')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Unit (glasses, pages…)')),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _freq,
          decoration: const InputDecoration(labelText: 'How often'),
          items: const [
            DropdownMenuItem(value: 'daily', child: Text('Every day')),
            DropdownMenuItem(value: 'weekdays', child: Text('Specific days of the week')),
            DropdownMenuItem(value: 'times', child: Text('A number of times per week')),
          ],
          onChanged: (v) => setState(() => _freq = v!),
        ),
        if (_freq == 'weekdays') ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < 7; i++)
              FilterChip(
                label: Text(_days[i]),
                showCheckmark: false,
                selected: (_weekdays >> i) & 1 == 1,
                onSelected: (v) => setState(() => _weekdays = v ? _weekdays | (1 << i) : _weekdays & ~(1 << i)),
              ),
          ]),
        ],
        if (_freq == 'times')
          Row(children: [
            const Text('Times per week'),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _times > 1 ? () => setState(() => _times--) : null),
            Text('$_times', style: Theme.of(context).textTheme.titleMedium),
            IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _times < 7 ? () => setState(() => _times++) : null),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.alarm),
              label: Text(_remind == null ? 'Add a daily reminder' : 'Remind me at $_remind'),
              onPressed: _pickTime,
            ),
          ),
          if (_remind != null)
            IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _remind = null)),
        ]),
        const SizedBox(height: 12),
        TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Why does this matter? (optional)')),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _save, child: const Text('Save')),
      ]),
    );
  }
}
