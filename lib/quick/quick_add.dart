import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../journal/journal_editor.dart';
import '../screens/expense_editor.dart';
import '../screens/habit_editor.dart';
import '../services/reminder_service.dart';
import '../sync/sync_log.dart';
import '../widgets/fx.dart';

/// Receives "add something" requests from home-screen widgets and app-icon shortcuts.
///
/// These only ever open a small *add* form. They show nothing that was written before,
/// and after saving the app closes again, still locked.
class QuickAddController extends ChangeNotifier {
  static const _channel = MethodChannel('myday/quick');

  /// expense | income | journal | journal_voice | task | reminder | habit
  String? action;

  /// Optional preset time for a reminder: hour | tonight | tomorrow
  String? when;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'quick') _set(Map<Object?, Object?>.from(call.arguments as Map));
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<Map<Object?, Object?>>('initial');
      if (initial != null) _set(initial);
    } catch (_) {}
  }

  void _set(Map<Object?, Object?> m) {
    action = m['action'] as String?;
    SyncLog.add('quick add opened: $action');
    when = m['when'] as String?;
    notifyListeners();
  }

  /// Shows a form directly (used by tests and by the Settings page).
  void open(String a, {String? preset}) {
    action = a;
    when = preset;
    notifyListeners();
  }

  /// Done: forget the request and leave the app.
  void finish() {
    action = null;
    when = null;
    notifyListeners();
    SystemNavigator.pop();
  }

  /// Asks Android to add one of our widgets to the home screen (a system dialog confirms).
  Future<bool> pinWidget(String name) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('pinWidget', name) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// The page shown when a widget button or shortcut was tapped.
class QuickAddScreen extends StatelessWidget {
  const QuickAddScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quick = context.watch<QuickAddController>();
    final action = quick.action ?? '';
    final body = switch (action) {
      'expense' || 'income' => _QuickMoney(kind: action),
      'journal' || 'journal_voice' => JournalEditor(onFinished: quick.finish, autoRecord: action == 'journal_voice'),
      'task' || 'reminder' => _QuickTask(reminder: action == 'reminder', preset: quick.when),
      'habit' => HabitForm(onDone: () async {
          await context.read<ReminderService>().reschedule();
          quick.finish();
        }),
      _ => const SizedBox.shrink(),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && action != 'journal' && action != 'journal_voice') quick.finish();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: body)),
        ),
      ),
    );
  }
}

class _QuickMoney extends StatelessWidget {
  const _QuickMoney({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final quick = context.read<QuickAddController>();
    return ExpenseForm(kind: kind, onDone: quick.finish);
  }
}

/// A fast "new task" / "new reminder" form.
class _QuickTask extends StatefulWidget {
  const _QuickTask({required this.reminder, this.preset});
  final bool reminder;
  final String? preset;

  @override
  State<_QuickTask> createState() => _QuickTaskState();
}

class _QuickTaskState extends State<_QuickTask> {
  final _title = TextEditingController();
  DateTime? _due;

  @override
  void initState() {
    super.initState();
    final w = widget.preset ?? (widget.reminder ? 'hour' : null);
    if (w != null) _due = _preset(w);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  static DateTime _preset(String w) {
    final now = DateTime.now();
    switch (w) {
      case 'tonight':
        final t = DateTime(now.year, now.month, now.day, 20);
        return t.isAfter(now) ? t : now.add(const Duration(hours: 1));
      case 'tomorrow':
        return DateTime(now.year, now.month, now.day + 1, 9);
      default:
        return DateTime(now.year, now.month, now.day, now.hour, now.minute).add(const Duration(hours: 1));
    }
  }

  Future<void> _pick() async {
    final base = _due ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final store = context.read<DataStore>();
    final reminders = context.read<ReminderService>();
    final quick = context.read<QuickAddController>();
    await store.saveTask(Task(
      id: const Uuid().v4(),
      title: _title.text.trim(),
      due: _due,
      remind: _due != null,
    ));
    await reminders.reschedule(); // so the alarm exists even though the app closes right away
    quick.finish();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final quick = context.read<QuickAddController>();

    Widget chip(String label, IconData icon, DateTime? value, {bool none = false}) {
      final selected = none ? _due == null : (_due != null && value != null && _due!.difference(value).abs() < const Duration(minutes: 1));
      return ChoiceChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _due = none ? null : value),
      );
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Icon(widget.reminder ? Icons.notifications_active_outlined : Icons.check_circle_outline, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.reminder ? 'New reminder' : 'New task', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
        IconButton(icon: const Icon(Icons.close), onPressed: quick.finish),
      ]),
      const SizedBox(height: 16),
      TextField(
        controller: _title,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.reminder ? 'Remind me to…' : 'What needs doing?'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _title.text.trim().isEmpty ? null : _save(),
      ),
      const SizedBox(height: 16),
      Text('When', style: tt.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (!widget.reminder) chip('No time', Icons.block, null, none: true),
        chip('In 1 hour', Icons.schedule, _preset('hour')),
        chip('Tonight', Icons.nights_stay_outlined, _preset('tonight')),
        chip('Tomorrow', Icons.wb_sunny_outlined, _preset('tomorrow')),
        ActionChip(avatar: const Icon(Icons.edit_calendar_outlined, size: 18), label: const Text('Pick…'), onPressed: _pick),
      ]),
      if (_due != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('You will be reminded ${DateFormat('EEE, d MMM · h:mm a').format(_due!)}')),
          ]),
        ),
      const SizedBox(height: 24),
      FilledButton(onPressed: _title.text.trim().isEmpty ? null : _save, child: Text(widget.reminder ? 'Set reminder' : 'Add task')),
      const SizedBox(height: 10),
      Text('Saved right away. Nothing you wrote before is shown here.', textAlign: TextAlign.center, style: tt.bodySmall),
    ]);
  }
}

/// Which widgets can be added from Settings.
class WidgetInfo {
  const WidgetInfo(this.name, this.title, this.subtitle, this.icon);
  final String name; // the Android class name
  final String title;
  final String subtitle;
  final IconData icon;
}

const availableWidgets = [
  WidgetInfo('MoneyWidget', 'Money', 'Income and expense, side by side', Icons.account_balance_wallet_outlined),
  WidgetInfo('JournalWidget', 'Quick journal', 'A writing idea, plus Write and Voice', Icons.menu_book_outlined),
  WidgetInfo('TaskWidget', 'Tasks & reminders', 'Add a task or a reminder in one tap', Icons.checklist_rounded),
  WidgetInfo('HabitWidget', 'Habits', 'Start a new habit or open the app', Icons.local_fire_department_outlined),
  WidgetInfo('QuickMediumWidget', 'Quick add (medium)', 'All six actions with labels', Icons.bolt_rounded),
  WidgetInfo('QuickBarWidget', 'Quick add (small bar)', 'All the actions as icons in one row', Icons.more_horiz_rounded),
];

class WidgetsSettingsPage extends StatelessWidget {
  const WidgetsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final quick = context.read<QuickAddController>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Home screen widgets')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: revealAll([
            Glass(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lock_outline_rounded, color: cs.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Widgets only add things. They never show what you wrote before, and they work without your PIN. '
                      'Everything else stays behind your PIN.'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            for (final w in availableWidgets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(w.icon, color: cs.primary),
                    title: Text(w.title),
                    subtitle: Text(w.subtitle),
                    trailing: FilledButton.tonal(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await quick.pinWidget(w.name);
                        if (!ok) {
                          messenger.showSnackBar(const SnackBar(
                              content: Text('Your launcher cannot add it from here. Long-press your home screen > Widgets > MyDay.')));
                        }
                      },
                      child: const Text('Add'),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text('Tip: touch and hold the MyDay app icon for shortcuts: Add expense, Add income, New journal entry, New task.',
                style: Theme.of(context).textTheme.bodySmall),
          ])),
        ),
      ),
    );
  }
}
