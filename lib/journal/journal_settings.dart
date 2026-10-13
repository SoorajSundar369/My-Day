import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../widgets/pin_pad.dart';

/// Minutes you can pick for "ask for the PIN again after leaving the journal".
const _graceSteps = [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120];

String graceLabel(int m) {
  if (m == 0) return 'Every time I open it';
  if (m < 60) return '$m minute${m == 1 ? '' : 's'}';
  final h = m ~/ 60, r = m % 60;
  final hours = '$h hour${h == 1 ? '' : 's'}';
  return r == 0 ? hours : '$hours $r min';
}

Future<String?> _askPin(BuildContext context, {required int length, required String title}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: PinPad(length: length, onComplete: (p) => Navigator.pop(ctx, p)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
    ),
  );
}

/// Asks for a new PIN twice. Returns it, or null if cancelled.
Future<String?> createJournalPin(BuildContext context, int length) async {
  while (true) {
    final a = await _askPin(context, length: length, title: 'Choose a $length-digit PIN');
    if (a == null || !context.mounted) return null;
    final b = await _askPin(context, length: length, title: 'Type it again to confirm');
    if (b == null || !context.mounted) return null;
    if (a == b) return a;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Those PINs didn't match. Try again.")));
  }
}

/// The journal's options: lock type, how long it stays unlocked, daily reminder.
class JournalSettingsBody extends StatelessWidget {
  const JournalSettingsBody({super.key});

  Future<void> _changeLock(BuildContext context) async {
    final s = context.read<SettingsService>();
    if (s.journalSetupDone) {
      final len = s.journalMode == 'own' ? s.journalPinLen : 4;
      final current = await _askPin(context, length: len, title: 'Enter your current journal PIN');
      if (current == null || !context.mounted) return;
      if (!s.checkJournalPin(current)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That PIN is not right.')));
        return;
      }
    }
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.lock_outline_rounded), title: const Text('Use my app PIN'), onTap: () => Navigator.pop(ctx, 'app')),
          ListTile(leading: const Icon(Icons.key_rounded), title: const Text('Separate PIN · 4 digits'), onTap: () => Navigator.pop(ctx, 'own4')),
          ListTile(leading: const Icon(Icons.key_rounded), title: const Text('Separate PIN · 6 digits'), onTap: () => Navigator.pop(ctx, 'own6')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'app') {
      await s.completeJournalSetup(mode: 'app');
    } else {
      final len = choice == 'own6' ? 6 : 4;
      final pin = await createJournalPin(context, len);
      if (pin == null) return;
      await s.completeJournalSetup(mode: 'own', length: len, pin: pin);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Journal lock updated')));
    }
  }

  Future<void> _pickReminderTime(BuildContext context, SettingsService s) async {
    final p = s.journalReminder.isEmpty ? null : s.journalReminder.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: p == null ? const TimeOfDay(hour: 21, minute: 0) : TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    if (t != null) await s.set('journalRemind', '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final idx = _graceSteps.indexOf(s.journalGraceMinutes).clamp(0, _graceSteps.length - 1);
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.lock_outline_rounded),
        title: const Text('Journal lock'),
        subtitle: Text(!s.journalSetupDone
            ? 'Not set up yet (you will be asked when you open the journal)'
            : (s.journalMode == 'app' ? 'Uses your app PIN' : 'Separate ${s.journalPinLen}-digit PIN')),
        trailing: TextButton(onPressed: () => _changeLock(context), child: const Text('Change')),
      ),
      ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: const Text('Ask for the PIN again'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 2),
          Text(graceLabel(s.journalGraceMinutes), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          Slider(
            min: 0,
            max: (_graceSteps.length - 1).toDouble(),
            divisions: _graceSteps.length - 1,
            value: idx.toDouble(),
            onChanged: (v) => s.set('journalGrace', _graceSteps[v.round()]),
          ),
          const Text('Left to right: every time, then up to 2 hours after you leave the journal.',
              style: TextStyle(fontSize: 12)),
        ]),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.alarm_rounded),
        title: const Text('Daily reminder to write'),
        subtitle: Text(s.journalReminder.isEmpty ? 'Off' : 'Every day at ${s.journalReminder}'),
        value: s.journalReminder.isNotEmpty,
        onChanged: (v) => v ? _pickReminderTime(context, s) : s.set('journalRemind', ''),
      ),
      if (s.journalReminder.isNotEmpty)
        ListTile(
          contentPadding: const EdgeInsets.only(left: 72, right: 16),
          title: const Text('Reminder time'),
          trailing: TextButton(onPressed: () => _pickReminderTime(context, s), child: Text(s.journalReminder)),
        ),
    ]);
  }
}

class JournalSettingsPage extends StatelessWidget {
  const JournalSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Journal settings')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(16), children: const [Card(child: JournalSettingsBody())]),
          ),
        ),
      );
}
