import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/data_store.dart';
import '../data/habit_models.dart';
import '../data/habit_store.dart';
import '../data/journal_store.dart';
import '../data/models.dart';
import '../data/money_store.dart';
import 'desktop_service.dart';
import 'settings_service.dart';

/// Polls for due reminders and shows Windows toast notifications.
///
/// Notification payloads / button arguments look like `verb|kind|id`,
/// e.g. `snooze|task|<uuid>` or `done|habit|<uuid>`.
class ReminderService with WidgetsBindingObserver {
  ReminderService(this.store, this.habits, this.money, this.settings, this.desktop);

  final DataStore store;
  final HabitStore habits;
  final MoneyStore money;
  final SettingsService settings;
  final DesktopService? desktop;
  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _timer;
  String? _iconPath;

  /// Set after creation so the journal reminder can tell whether you already wrote today.
  JournalStore? journal;
  String _journalNotifiedDay = '';

  // Fixed identity so Windows keeps the same notification settings across runs.
  static const _aumId = 'Sujay.MyDay';
  static const _guid = 'b3f1c7a2-5d4e-4c8b-9a61-7e2f0d3a91c4';

  static bool get supported => Platform.isWindows || Platform.isAndroid;

  Future<void> init() async {
    if (!supported) return;
    if (Platform.isAndroid) return _initAndroid();
    final dir = await getApplicationSupportDirectory();
    final icon = File(p.join(dir.path, 'toast_icon.png'));
    await icon.writeAsBytes(
        (await rootBundle.load('assets/toast_icon.png')).buffer.asUint8List(),
        flush: true);
    _iconPath = icon.path;

    await _plugin.initialize(
      settings: InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: settings.appName,
          appUserModelId: _aumId,
          guid: _guid,
          iconPath: icon.path,
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => check());
    check();
  }

  Future<void> check() async {
    final now = DateTime.now();
    final due = store.tasks
        .where((t) => t.remind && !t.done && !t.notified && t.due != null && !t.due!.isAfter(now))
        .toList();
    for (final t in due) {
      await store.markTaskNotified(t);
      await _toast(t);
    }

    for (final h in habits.dueReminders(now)) {
      await habits.markNotified(h);
      await _habitToast(h);
    }
    await _checkJournalReminder(now);
    await money.processRecurring();
  }

  Future<void> _checkJournalReminder(DateTime now) async {
    final t = settings.journalReminder;
    final j = journal;
    if (t.isEmpty || j == null || j.writtenToday) return;
    final key = '${now.year}-${now.month}-${now.day}';
    if (_journalNotifiedDay == key) return;
    final p = t.split(':');
    final at = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
    if (now.isBefore(at)) return;
    _journalNotifiedDay = key;
    final hide = settings.hideNotifContent;
    await _plugin.show(
      id: 7002,
      title: hide ? 'Reminder' : 'Time to write in your journal',
      body: hide ? 'You have a reminder' : 'A few lines about today, ${settings.callName}?',
      payload: 'open|journal|0',
      notificationDetails: _details(const []),
    );
  }

  /// Handles clicks on a toast or on one of its buttons.
  Future<void> _onResponse(NotificationResponse r) async {
    if (Platform.isAndroid) return; // tapping a phone notification just opens the app
    final parts = (r.actionId ?? r.payload ?? '').split('|');
    if (parts.length != 3) {
      await desktop?.showWindow();
      return;
    }
    final verb = parts[0], kind = parts[1], id = parts[2];
    if (kind == 'task') {
      final t = store.tasks.where((e) => e.id == id).firstOrNull;
      if (t == null) return;
      if (verb == 'snooze') {
        await store.snooze(t, Duration(minutes: settings.snoozeMinutes));
      } else if (verb == 'done') {
        await store.toggleDone(t);
      } else {
        await desktop?.showWindow();
      }
    } else if (kind == 'habit') {
      final h = habits.habits.where((e) => e.id == id).firstOrNull;
      if (h == null) return;
      if (verb == 'done') {
        if (!habits.doneOn(h, DateTime.now())) await habits.toggle(h, DateTime.now());
      } else {
        await desktop?.showWindow();
      }
    } else {
      await desktop?.showWindow();
    }
  }

  NotificationDetails _details(List<WindowsAction> actions) => NotificationDetails(
        windows: WindowsNotificationDetails(
          actions: actions,
          images: [
            if (_iconPath != null)
              WindowsImage(Uri.file(_iconPath!, windows: true),
                  altText: settings.appName, placement: WindowsImagePlacement.appLogoOverride),
          ],
        ),
      );

  int _nid(String id) => id.hashCode & 0x7fffffff;

  Future<void> _toast(Task t) async {
    final hide = settings.hideNotifContent;
    await _plugin.show(
      id: _nid(t.id),
      title: hide ? 'Reminder' : t.title,
      body: hide
          ? 'You have a reminder'
          : (t.description.isNotEmpty ? t.description : 'Reminder from ${settings.appName}'),
      payload: 'open|task|${t.id}',
      notificationDetails: _details([
        WindowsAction(
            content: 'Snooze ${settings.snoozeMinutes} min', arguments: 'snooze|task|${t.id}'),
        WindowsAction(content: 'Done', arguments: 'done|task|${t.id}'),
      ]),
    );
  }

  Future<void> _habitToast(Habit h) async {
    final hide = settings.hideNotifContent;
    await _plugin.show(
      id: _nid(h.id),
      title: hide ? 'Reminder' : 'Time for: ${h.name}',
      body: hide ? 'You have a reminder' : 'Keep your streak going, ${settings.callName}.',
      payload: 'open|habit|${h.id}',
      notificationDetails: _details([
        WindowsAction(content: 'Mark done', arguments: 'done|habit|${h.id}'),
      ]),
    );
  }

  Future<void> test() async {
    if (!supported) return;
    if (Platform.isAndroid) {
      await _plugin.show(
        id: 1,
        title: settings.appName,
        body: 'Notifications are working, ${settings.callName}!',
        notificationDetails: _androidDetails(),
      );
      return;
    }
    await _plugin.show(
      id: 1,
      title: settings.appName,
      body: 'Notifications are working, ${settings.callName}!',
      payload: 'open|test|0',
      notificationDetails: _details(const []),
    );
  }

  // ───────────── Android: schedule reminders with the system alarm clock ─────────────
  //
  // The phone never polls. Every reminder is handed to Android as an exact alarm,
  // so it fires even when the app is closed, costing no battery while waiting.

  Timer? _resched;

  static const _androidChannel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Task and habit reminders',
    importance: Importance.high,
    priority: Priority.high,
  );

  NotificationDetails _androidDetails() => const NotificationDetails(android: _androidChannel);

  /// Lightweight setup for the background sync task (no permission prompts, no listeners).
  Future<void> initForBackground() async {
    if (!Platform.isAndroid) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {}
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
  }

  /// A plain notification (used for "synced N changes" and "large files waiting").
  Future<void> showInfo(String title, String body) async {
    if (!Platform.isAndroid) return;
    await _plugin.show(
      id: 7001,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('sync', 'Sync',
            channelDescription: 'Messages about syncing with your computer',
            importance: Importance.defaultImportance),
      ),
    );
  }

  Future<void> _initAndroid() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {}
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    if (await android?.canScheduleExactNotifications() == false) {
      await android?.requestExactAlarmsPermission();
    }
    store.addListener(_scheduleSoon);
    habits.addListener(_scheduleSoon);
    WidgetsBinding.instance.addObserver(this);
    await reschedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleSoon();
  }

  void _scheduleSoon() {
    _resched?.cancel();
    _resched = Timer(const Duration(seconds: 2), reschedule);
  }

  /// Re-creates every upcoming alarm from the current data (cheap, runs after any change).
  Future<void> reschedule() async {
    if (!Platform.isAndroid) return;
    await _plugin.cancelAll();
    final now = DateTime.now();
    final hide = settings.hideNotifContent;
    var count = 0;

    final upcoming = store.tasks
        .where((t) => t.remind && !t.done && t.due != null && t.due!.isAfter(now))
        .toList()
      ..sort((a, b) => a.due!.compareTo(b.due!));
    for (final t in upcoming.take(60)) {
      await _schedule(
        _nid(t.id),
        t.due!,
        hide ? 'Reminder' : t.title,
        hide ? 'You have a reminder' : (t.description.isNotEmpty ? t.description : 'Reminder from ${settings.appName}'),
        'open|task|${t.id}',
      );
      count++;
    }

    // Journal reminder for the next 7 days (skips today if you already wrote).
    final jt = settings.journalReminder;
    if (jt.isNotEmpty) {
      final p = jt.split(':');
      for (var i = 0; i < 7; i++) {
        final day = DateTime(now.year, now.month, now.day + i);
        final at = DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
        if (!at.isAfter(now)) continue;
        if (i == 0 && (journal?.writtenToday ?? false)) continue;
        await _schedule(
          _nid('journal-${day.year}${day.month}${day.day}'),
          at,
          hide ? 'Reminder' : 'Time to write in your journal',
          hide ? 'You have a reminder' : 'A few lines about today, ${settings.callName}?',
          'open|journal|0',
        );
        count++;
      }
    }

    // Habit reminders for the next 7 days (skips days already done).
    for (final h in habits.active.where((h) => h.remindTime != null)) {
      final parts = h.remindTime!.split(':');
      for (var i = 0; i < 7 && count < 200; i++) {
        final day = DateTime(now.year, now.month, now.day + i);
        final at = DateTime(day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
        if (!at.isAfter(now)) continue;
        if (!habits.scheduledOn(h, day) || habits.doneOn(h, day)) continue;
        await _schedule(
          _nid('${h.id}-${day.year}${day.month}${day.day}'),
          at,
          hide ? 'Reminder' : 'Time for: ${h.name}',
          hide ? 'You have a reminder' : 'Keep your streak going, ${settings.callName}.',
          'open|habit|${h.id}',
        );
        count++;
      }
    }
  }

  Future<void> _schedule(int id, DateTime when, String title, String body, String payload) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _androidDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {
      // Exact alarms not allowed: fall back to an inexact one so the reminder still arrives.
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _androidDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  void dispose() {
    _timer?.cancel();
    _resched?.cancel();
  }
}
