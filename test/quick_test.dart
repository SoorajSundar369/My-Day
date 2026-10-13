import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taskme/core/theme.dart';
import 'package:taskme/data/data_store.dart';
import 'package:taskme/data/habit_models.dart';
import 'package:taskme/data/habit_store.dart';
import 'package:taskme/data/journal_models.dart';
import 'package:taskme/data/journal_store.dart';
import 'package:taskme/data/models.dart';
import 'package:taskme/data/money_store.dart';
import 'package:taskme/quick/quick_add.dart';
import 'package:taskme/services/reminder_service.dart';
import 'package:taskme/services/settings_service.dart';
import 'package:taskme/services/sound_service.dart';
import 'package:taskme/widgets/fx.dart';

void main() {
  sqfliteFfiInit();

  late DataStore store;
  late MoneyStore money;
  late HabitStore habits;
  late JournalStore journal;
  late SettingsService settings;
  late QuickAddController quick;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    await settings.set('motion', 0);
    store = DataStore();
    await store.init(dir: await Directory.systemTemp.createTemp('myday_quick'), factory: databaseFactoryFfi);
    money = MoneyStore(store, settings);
    habits = HabitStore(store, settings);
    journal = JournalStore(store);
    await money.load();
    await habits.load();
    await journal.load();
    quick = QuickAddController();
  });

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<DataStore>.value(value: store),
          ChangeNotifierProvider<MoneyStore>.value(value: money),
          ChangeNotifierProvider<HabitStore>.value(value: habits),
          ChangeNotifierProvider<JournalStore>.value(value: journal),
          ChangeNotifierProvider<QuickAddController>.value(value: quick),
          Provider<SoundService>.value(value: SoundService(settings, silent: true)),
          Provider<ReminderService>.value(value: ReminderService(store, habits, money, settings, null)),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF4F6BED), Brightness.dark),
          builder: (c, child) => AuroraBackground(child: child!),
          home: Builder(builder: (context) => context.watch<QuickAddController>().action == null ? const Scaffold(body: Text('HOME')) : const QuickAddScreen()),
        ),
      );

  Future<void> realIo(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(milliseconds: 100)); // let the code after the database write run
    await t.pump(const Duration(milliseconds: 100));
  }

  void bigScreen(WidgetTester t) {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
  }

  testWidgets('quick expense: type an amount, save, and the app closes again', (t) async {
    bigScreen(t);
    quick.open('expense');
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '120');
    await t.pump();
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    await realIo(t);
    expect(money.expenses.single.amount, 120);
    expect(money.expenses.single.isIncome, isFalse);
    expect(quick.action, isNull); // finished: back to nothing
  });

  testWidgets('quick income is saved as income', (t) async {
    bigScreen(t);
    quick.open('income');
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '5000');
    await t.pump();
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    await realIo(t);
    expect(money.expenses.single.isIncome, isTrue);
    expect(money.expenses.single.amount, 5000);
  });

  testWidgets('quick reminder from the "Tonight" chip creates a task with a notification time', (t) async {
    bigScreen(t);
    quick.open('reminder', preset: 'tonight');
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Take medicine');
    await t.pump();
    await t.tap(find.text('Set reminder'));
    await t.pumpAndSettle();
    await realIo(t);
    final task = store.tasks.single;
    expect(task.title, 'Take medicine');
    expect(task.remind, isTrue);
    expect(task.due, isNotNull);
    expect(task.due!.isAfter(DateTime.now()), isTrue);
    expect(quick.action, isNull);
  });

  testWidgets('quick task without a time is just a task', (t) async {
    bigScreen(t);
    quick.open('task');
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Buy milk');
    await t.pump();
    await t.tap(find.text('Add task'));
    await t.pumpAndSettle();
    await realIo(t);
    expect(store.tasks.single.title, 'Buy milk');
    expect(store.tasks.single.remind, isFalse);
    expect(store.tasks.single.due, isNull);
  });

  testWidgets('quick journal entry saves when you tap Done', (t) async {
    bigScreen(t);
    quick.open('journal');
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(1), 'Wrote this from the widget');
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    await realIo(t);
    expect(journal.entries.single.body, 'Wrote this from the widget');
    expect(quick.action, isNull);
  });

  testWidgets('quick habit creates a habit', (t) async {
    bigScreen(t);
    quick.open('habit');
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Stretch');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    await realIo(t);
    expect(habits.habits.single.name, 'Stretch');
  });

  // one test per screen so a problem points at the exact screen
  for (final kind in ['expense', 'income', 'journal', 'task', 'reminder', 'habit']) {
    testWidgets('privacy: the $kind screen shows nothing that was saved before', (t) async {
      bigScreen(t);
      await t.runAsync(() async {
        await store.saveTask(Task(id: 't', title: 'SECRET-TASK', due: DateTime.now().add(const Duration(hours: 3)), remind: true));
        await money.save(Expense(id: 'e', amount: 4242, category: 'food', note: 'SECRET-NOTE'));
        await journal.save(JournalEntry(id: 'j', title: 'SECRET-ENTRY', body: 'SECRET-BODY'));
        await habits.save(Habit(id: 'h', name: 'SECRET-HABIT'));
      });

      quick.open(kind);
      await t.pumpWidget(app());
      await t.pump(const Duration(milliseconds: 800));
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining('4242'), findsNothing);
    });
  }
}
