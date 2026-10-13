import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/data_store.dart';
import 'data/habit_store.dart';
import 'data/journal_store.dart';
import 'data/money_store.dart';
import 'quick/quick_add.dart';
import 'services/biometric_service.dart';
import 'services/desktop_service.dart';
import 'services/journal_lock.dart';
import 'services/lock_controller.dart';
import 'services/reminder_service.dart';
import 'services/settings_service.dart';
import 'services/sound_service.dart';
import 'sync/background_sync.dart';
import 'sync/sync_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  await settings.init();
  final store = DataStore();
  await store.init();
  final habits = HabitStore(store, settings);
  final money = MoneyStore(store, settings);
  final journal = JournalStore(store);
  final journalLock = JournalLock(settings);
  await habits.load();
  await money.load();
  await journal.load();
  final sound = SoundService(settings);
  await sound.init();
  final lock = LockController(settings)..onUnlocked = () => sound.play(Sfx.unlock);
  lock.addListener(() {
    if (lock.locked) journalLock.lockNow(); // locking the app locks the journal too
  });
  final desktop = DesktopService(settings, lock);
  await desktop.init(startHidden: args.contains('--hidden'));
  final reminders = ReminderService(store, habits, money, settings, desktop)..journal = journal;
  await reminders.init();
  final quick = QuickAddController();
  await BackgroundSync.init();
  final sync = SyncService(store: store, settings: settings);
  await sync.init();
  sync.onDataApplied = reminders.reschedule;
  await quick.init(); // after sync.init so the request is also written to the log

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: store),
      ChangeNotifierProvider.value(value: habits),
      ChangeNotifierProvider.value(value: money),
      ChangeNotifierProvider.value(value: journal),
      ChangeNotifierProvider.value(value: journalLock),
      ChangeNotifierProvider.value(value: lock),
      ChangeNotifierProvider.value(value: quick),
      ChangeNotifierProvider.value(value: sync),
      Provider.value(value: sound),
      Provider.value(value: BiometricService()),
      Provider.value(value: desktop),
      Provider.value(value: reminders),
    ],
    child: const TaskmeApp(),
  ));
}
