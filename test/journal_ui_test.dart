import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taskme/core/theme.dart';
import 'package:taskme/data/data_store.dart';
import 'package:taskme/data/journal_store.dart';
import 'package:taskme/journal/journal_editor.dart';
import 'package:taskme/journal/journal_gate.dart';
import 'package:taskme/journal/journal_settings.dart';
import 'package:taskme/services/journal_lock.dart';
import 'package:taskme/services/settings_service.dart';
import 'package:taskme/services/sound_service.dart';
import 'package:taskme/widgets/fx.dart';

void main() {
  sqfliteFfiInit();

  late DataStore store;
  late JournalStore journal;
  late SettingsService settings;
  late JournalLock lock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    await settings.set('motion', 0); // no endless background animation, so tests can settle
    store = DataStore();
    await store.init(dir: await Directory.systemTemp.createTemp('myday_ui'), factory: databaseFactoryFfi);
    journal = JournalStore(store);
    await journal.load();
    lock = JournalLock(settings);
  });

  Widget app(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<JournalStore>.value(value: journal),
          ChangeNotifierProvider<JournalLock>.value(value: lock),
          ChangeNotifierProvider<DataStore>.value(value: store),
          Provider<SoundService>.value(value: SoundService(settings, silent: true)),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF4F6BED), Brightness.dark),
          builder: (c, child) => AuroraBackground(child: child!),
          home: Scaffold(body: child),
        ),
      );

  Future<void> typePin(WidgetTester t, String pin) async {
    for (final d in pin.split('')) {
      await t.tap(find.text(d).last);
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('first open: choose app PIN, book opens, PIN unlocks the journal', (t) async {
    t.view.physicalSize = const Size(900, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await settings.setPin('2468');

    await t.pumpWidget(app(const JournalGate()));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Protect your journal'), findsOneWidget);

    await t.tap(find.text('Use my app PIN'));
    await t.pump(const Duration(milliseconds: 100));
    // the book cover animates open, then the PIN page appears
    await t.pump(const Duration(milliseconds: 700));
    expect(find.text('Journal'), findsWidgets); // the cover
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Enter your app PIN'), findsOneWidget);

    await typePin(t, '1111'); // wrong
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    expect(lock.isOpen, isFalse);

    await typePin(t, '2468'); // right
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(seconds: 1));
    expect(lock.isOpen, isTrue);
    expect(find.text('New entry'), findsOneWidget); // the journal home
    expect(tester(t), isNull);
  });

  testWidgets('separate 6-digit PIN setup', (t) async {
    t.view.physicalSize = const Size(900, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);

    await t.pumpWidget(app(const JournalGate()));
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Use a separate journal PIN'));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('6 digits'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Next'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Create your journal PIN'), findsOneWidget);
    await typePin(t, '135790');
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Type it again to confirm'), findsOneWidget);
    await typePin(t, '135790');
    await t.pump(const Duration(milliseconds: 800));
    expect(settings.journalSetupDone, isTrue);
    expect(settings.journalMode, 'own');
    expect(settings.journalPinLen, 6);
    expect(settings.checkJournalPin('135790'), isTrue);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('editor: write, format, mood, bookmark and it saves on leaving', (t) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);

    await t.pumpWidget(app(Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalEditor())),
          child: const Text('open'),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.enterText(find.widgetWithText(TextField, 'Title (optional)').first, 'My day');
    await t.enterText(find.byType(TextField).at(1), 'Hello world');
    await t.tap(find.byIcon(Icons.format_bold_rounded));
    await t.pump();
    await t.tap(find.text('😄'));
    await t.pump();
    await t.tap(find.byIcon(Icons.bookmark_border_rounded));
    await t.pump();
    await t.tap(find.byIcon(Icons.visibility_outlined)); // preview works
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    // saving touches the real database, which finishes outside the test clock
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));

    final e = journal.entries.single;
    expect(e.title, 'My day');
    expect(e.mood, 5);
    expect(e.bookmarked, isTrue);
    expect(e.body, contains('Hello world'));
    expect(e.body, contains('**')); // bold markers were inserted
  });

  testWidgets('an empty new entry is not saved', (t) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(app(Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalEditor())),
          child: const Text('open'),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(journal.entries, isEmpty);
  });

  testWidgets('journal settings: grace slider reaches 2 hours', (t) async {
    t.view.physicalSize = const Size(900, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(app(const SingleChildScrollView(child: JournalSettingsBody())));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Every time I open it'), findsOneWidget);
    await t.drag(find.byType(Slider), const Offset(2000, 0));
    await t.pump(const Duration(milliseconds: 300));
    expect(settings.journalGraceMinutes, 120);
    expect(find.text('2 hours'), findsOneWidget);
    expect(graceLabel(90), '1 hour 30 min');
  });
}

Object? tester(WidgetTester t) => t.takeException();
