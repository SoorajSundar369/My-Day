import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/data_store.dart';
import '../data/habit_store.dart';
import '../data/money_store.dart';
import '../services/reminder_service.dart';
import '../services/settings_service.dart';
import 'sync_service.dart';

const _uniqueName = 'myday-sync-check';
const _taskName = 'syncCheck';

/// Runs in a background process roughly every 30 minutes (Android decides the exact
/// moment to save battery): connect to the computer if it is on the same Wi-Fi,
/// exchange changes, reschedule reminders, and show a notification if something arrived.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await _runOnce();
    } catch (_) {}
    return true;
  });
}

Future<void> _runOnce() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.init();
  if (!settings.setupDone) return;

  final store = DataStore();
  await store.init();
  final habits = HabitStore(store, settings);
  final money = MoneyStore(store, settings);
  await habits.load();
  await money.load();

  final reminders = ReminderService(store, habits, money, settings, null);
  await reminders.initForBackground();

  final sync = SyncService(store: store, settings: settings, hub: false);
  await sync.initCore();
  final applied = await sync.backgroundSyncOnce();

  if (applied > 0) {
    await reminders.reschedule();
    if (sync.notifyOnChanges) {
      await reminders.showInfo(
          'MyDay synced', '$applied change${applied == 1 ? '' : 's'} from ${sync.peers.first.name}');
    }
  }
  if (sync.pendingFiles.isNotEmpty) {
    final n = sync.pendingFiles.length;
    await reminders.showInfo('Large file${n == 1 ? '' : 's'} waiting',
        '$n file${n == 1 ? ' is' : 's are'} over 10 MB. Open MyDay to choose whether to copy ${n == 1 ? 'it' : 'them'}.');
  }
}

class BackgroundSync {
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(backgroundDispatcher);
  }

  /// Turns the periodic check on or off.
  static Future<void> setEnabled(bool on) async {
    if (!Platform.isAndroid) return;
    if (on) {
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.unmetered, requiresBatteryNotLow: true),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await Workmanager().cancelByUniqueName(_uniqueName);
    }
  }
}
