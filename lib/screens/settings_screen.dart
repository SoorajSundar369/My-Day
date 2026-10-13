import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/data_store.dart';
import '../services/desktop_service.dart';
import '../services/reminder_service.dart';
import '../services/settings_service.dart';
import '../journal/journal_settings.dart';
import '../quick/quick_add.dart';
import '../services/biometric_service.dart';
import 'biometric_tiles.dart';
import '../sync/sync_screen.dart';
import '../sync/sync_service.dart';
import '../widgets/fx.dart';
import '../widgets/pin_pad.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<String?> _askText(BuildContext context, String title, String initial,
      {String? help}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (help != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(help)),
          TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
        ],
      ),
    );
  }

  /// Asks for the current PIN; returns true if correct.
  Future<bool> _checkPin(BuildContext context, {String title = 'Enter your current PIN'}) async {
    final s = context.read<SettingsService>();
    final key = GlobalKey<PinPadState>();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            PinPad(
              key: key,
              onComplete: (pin) {
                if (s.verifyPin(pin)) {
                  Navigator.pop(ctx, true);
                } else {
                  setState(() => err = 'Wrong PIN');
                  key.currentState?.clear();
                }
              },
            ),
            if (err != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))],
        ),
      ),
    );
    return ok ?? false;
  }

  Future<String?> _newPin(BuildContext context) async {
    final key = GlobalKey<PinPadState>();
    String? first;
    String? err;
    return showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(first == null ? 'Choose a new PIN' : 'Confirm new PIN'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            PinPad(
              key: key,
              onComplete: (pin) {
                if (first == null) {
                  setState(() {
                    first = pin;
                    err = null;
                  });
                  key.currentState?.clear();
                } else if (first == pin) {
                  Navigator.pop(ctx, pin);
                } else {
                  setState(() {
                    first = null;
                    err = "PINs didn't match";
                  });
                  key.currentState?.clear();
                }
              },
            ),
            if (err != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        ),
      ),
    );
  }

  Future<void> _changeQuestion(BuildContext context) async {
    final s = context.read<SettingsService>();
    if (!await _checkPin(context)) return;
    if (!context.mounted) return;
    final q = TextEditingController(text: s.securityQuestion);
    final a = TextEditingController();
    final h = TextEditingController(text: s.securityHint);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Security question'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: q, decoration: const InputDecoration(labelText: 'Question')),
          const SizedBox(height: 10),
          TextField(controller: a, decoration: const InputDecoration(labelText: 'New answer')),
          const SizedBox(height: 10),
          TextField(controller: h, decoration: const InputDecoration(labelText: 'Hint (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && q.text.trim().isNotEmpty && a.text.trim().isNotEmpty) {
      await s.setSecurity(question: q.text.trim(), answer: a.text, hint: h.text.trim());
    }
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _backup(BuildContext context) async {
    final store = context.read<DataStore>();
    final s = context.read<SettingsService>();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save backup',
      fileName: '${s.appName}-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.zip',
      allowedExtensions: ['zip'],
      type: FileType.custom,
    );
    if (path == null) return;
    await store.exportBackup(path, s.exportAll());
    if (context.mounted) _snack(context, 'Backup saved');
  }

  Future<void> _restore(BuildContext context) async {
    final store = context.read<DataStore>();
    final s = context.read<SettingsService>();
    final res = await FilePicker
        .pickFiles(type: FileType.custom, allowedExtensions: ['zip'], dialogTitle: 'Choose backup');
    final path = res?.files.single.path;
    if (path == null || !context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text('This replaces ALL current tasks, notes, files and settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await s.importAll(await store.importBackup(path));
      if (context.mounted) _snack(context, 'Backup restored');
    } catch (e) {
      if (context.mounted) _snack(context, 'Restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final desktop = context.read<DesktopService>();
    final reminders = context.read<ReminderService>();

    Widget section(String t) => _SectionHeader(t);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: _grouped([
          section('Sync'),
          Builder(builder: (context) {
            final sync = context.watch<SyncService>();
            final text = switch (sync.status) {
              SyncStatus.notPaired => 'Not paired',
              SyncStatus.disabled => 'Off',
              SyncStatus.connected || SyncStatus.syncing => 'Connected · last synced ${agoText(sync.lastSync)}',
              SyncStatus.offline => 'Not on Wi-Fi',
              _ => 'Waiting for the other device',
            };
            return ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: Text(sync.isHub ? 'Sync with your phone' : 'Sync with your computer'),
              subtitle: Text(text),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen())),
            );
          }),
          section('Profile'),
          ListTile(
            title: const Text('Name'),
            subtitle: Text(s.name),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, 'Your name', s.name);
              if (v != null && v.trim().isNotEmpty) s.saveProfile(name: v.trim(), nickname: s.nickname);
            },
          ),
          ListTile(
            title: const Text('Nickname'),
            subtitle: Text(s.nickname),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, 'Nickname', s.nickname);
              if (v != null && v.trim().isNotEmpty) s.saveProfile(name: s.name, nickname: v.trim());
            },
          ),
          ListTile(
            title: const Text('Call me by'),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'nickname', label: Text('Nickname')),
                ButtonSegment(value: 'name', label: Text('Name')),
              ],
              selected: {s.callMeBy},
              onSelectionChanged: (v) => s.set('callMeBy', v.first),
            ),
          ),
          ListTile(
            title: const Text('Lock screen greeting'),
            subtitle: Text('${s.greetingTemplate}\nPreview: ${s.greeting()}'),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, 'Greeting', s.greetingTemplate,
                  help: 'Use {time} (morning/afternoon/evening), {call}, {name}, {nick}.');
              if (v != null && v.trim().isNotEmpty) s.set('greeting', v.trim());
            },
          ),
          ListTile(
            title: const Text('App name'),
            subtitle: Text(s.appName),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await _askText(context, 'App name', s.appName);
              if (v != null && v.trim().isNotEmpty) {
                await s.set('appName', v.trim());
                await desktop.rebuildTrayMenu();
              }
            },
          ),
          section('Appearance'),
          ListTile(
            title: const Text('Theme'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.brightness_auto), label: Text('System')),
                ButtonSegment(value: 1, icon: Icon(Icons.light_mode), label: Text('Light')),
                ButtonSegment(value: 2, icon: Icon(Icons.dark_mode), label: Text('Dark')),
              ],
              selected: {s.themeMode.index},
              onSelectionChanged: (v) => s.set('themeMode', v.first),
            ),
          ),
          ListTile(
            title: const Text('Accent colour'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < accentChoices.length; i++)
                  GestureDetector(
                    onTap: () => s.set('accent', i),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: accentChoices[i],
                      child: s.accentIndex == i
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
              ]),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_motion_outlined),
            title: const Text('Animations'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Off')),
                    ButtonSegment(value: 1, label: Text('Subtle')),
                    ButtonSegment(value: 2, label: Text('Balanced')),
                    ButtonSegment(value: 3, label: Text('Bold')),
                  ],
                  selected: {s.motionLevel},
                  onSelectionChanged: (v) => s.set('motion', v.first),
                ),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Sounds'),
            subtitle: const Text('Income, expense, unlock and journal sounds'),
            value: s.soundsOn,
            onChanged: (v) => s.set('sounds', v),
          ),
          if (Platform.isAndroid) ...[
            section('Widgets & shortcuts'),
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Home screen widgets'),
              subtitle: const Text('Quick add for money, journal, tasks and habits'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WidgetsSettingsPage())),
            ),
          ],
          section('Journal'),
          const JournalSettingsBody(),
          section('Habits & money'),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('Currency symbol'),
            trailing: DropdownButton<String>(
              value: ['₹', r'$', '€', '£', '¥'].contains(s.currency) ? s.currency : '₹',
              items: const [
                DropdownMenuItem(value: '₹', child: Text('₹  Rupee')),
                DropdownMenuItem(value: r'$', child: Text(r'$  Dollar')),
                DropdownMenuItem(value: '€', child: Text('€  Euro')),
                DropdownMenuItem(value: '£', child: Text('£  Pound')),
                DropdownMenuItem(value: '¥', child: Text('¥  Yen')),
              ],
              onChanged: (v) => s.set('currency', v!),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.view_week_outlined),
            title: const Text('Week starts on'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Monday')),
                ButtonSegment(value: 7, label: Text('Sunday')),
              ],
              selected: {s.weekStart},
              onSelectionChanged: (v) => s.set('weekStart', v.first),
            ),
          ),
          section('Security'),
          if (BiometricService.platformSupported) const BiometricTiles(),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Change PIN'),
            onTap: () async {
              if (!await _checkPin(context)) return;
              if (!context.mounted) return;
              final pin = await _newPin(context);
              if (pin != null) {
                await s.setPin(pin);
                if (context.mounted) _snack(context, 'PIN changed');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Security question & hint'),
            subtitle: Text(s.securityQuestion),
            onTap: () => _changeQuestion(context),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Auto-lock after inactivity'),
            trailing: DropdownButton<int>(
              value: s.autoLockMinutes,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Never')),
                DropdownMenuItem(value: 1, child: Text('1 minute')),
                DropdownMenuItem(value: 5, child: Text('5 minutes')),
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
              ],
              onChanged: (v) => s.set('autoLock', v!),
            ),
          ),
          if (DesktopService.supported)
            SwitchListTile(
              secondary: const Icon(Icons.lock_clock),
              title: const Text('Lock when sent to the system tray'),
              value: s.lockOnTray,
              onChanged: (v) => s.set('lockOnTray', v),
            ),
          section('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide reminder details'),
            subtitle: const Text('Notifications just say "You have a reminder"'),
            value: s.hideNotifContent,
            onChanged: (v) => s.set('hideNotif', v),
          ),
          ListTile(
            leading: const Icon(Icons.snooze),
            title: const Text('Snooze length'),
            trailing: DropdownButton<int>(
              value: s.snoozeMinutes,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 minutes')),
                DropdownMenuItem(value: 10, child: Text('10 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
                DropdownMenuItem(value: 60, child: Text('1 hour')),
              ],
              onChanged: (v) => s.set('snooze', v!),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Send a test notification'),
            onTap: reminders.test,
          ),
          if (DesktopService.supported) ...[
            section('Windows'),
            SwitchListTile(
              secondary: const Icon(Icons.minimize),
              title: const Text('Keep running in the system tray when closed'),
              subtitle: const Text('Needed so reminders still fire'),
              value: s.minimizeToTray,
              onChanged: (v) => s.set('tray', v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.power_settings_new),
              title: const Text('Start with Windows'),
              value: s.startWithWindows,
              onChanged: (v) async {
                await s.set('startup', v);
                await desktop.applyStartup();
              },
            ),
          ],
          section('Data'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Back up everything'),
            subtitle: const Text('Saves tasks, notes, files and settings to one .zip'),
            onTap: () => _backup(context),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore from backup'),
            onTap: () => _restore(context),
          ),
        ])),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 26, 8, 8),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
      );
}

/// Puts the tiles under each section header into one glass card.
List<Widget> _grouped(List<Widget> items) {
  final out = <Widget>[];
  var group = <Widget>[];
  var n = 0;
  void flush() {
    if (group.isEmpty) return;
    out.add(Reveal(
      index: n++,
      child: Card(child: Column(children: [...group])),
    ));
    group = [];
  }

  for (final w in items) {
    if (w is _SectionHeader) {
      flush();
      out.add(w);
    } else if (w is SizedBox) {
      continue;
    } else {
      group.add(w);
    }
  }
  flush();
  return out;
}
