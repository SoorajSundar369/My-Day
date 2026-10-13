import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taskme/core/theme.dart';
import 'package:taskme/data/data_store.dart';
import 'package:taskme/data/journal_store.dart';
import 'package:taskme/journal/journal_gate.dart';
import 'package:taskme/screens/biometric_tiles.dart';
import 'package:taskme/screens/lock_screen.dart';
import 'package:taskme/services/biometric_service.dart';
import 'package:taskme/services/journal_lock.dart';
import 'package:taskme/services/lock_controller.dart';
import 'package:taskme/services/settings_service.dart';
import 'package:taskme/services/sound_service.dart';
import 'package:taskme/widgets/fx.dart';

/// A pretend fingerprint sensor.
class FakeBio extends BiometricService {
  FakeBio({this.ok = true, this.present = true});
  bool ok;
  bool present;
  int prompts = 0;

  @override
  Future<bool> available() async => present;

  @override
  Future<bool> authenticate(String reason, {String closeLabel = 'Use PIN'}) async {
    prompts++;
    return ok;
  }
}

void main() {
  sqfliteFfiInit();
  late SettingsService settings;
  late LockController lock;
  late FakeBio bio;
  late DataStore store;
  late JournalStore journal;
  late JournalLock jlock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    await settings.set('motion', 0);
    await settings.setPin('2468');
    lock = LockController(settings);
    bio = FakeBio();
    store = DataStore();
    await store.init(dir: await Directory.systemTemp.createTemp('myday_bio'), factory: databaseFactoryFfi);
    journal = JournalStore(store);
    jlock = JournalLock(settings);
  });

  Widget app(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<LockController>.value(value: lock),
          ChangeNotifierProvider<JournalStore>.value(value: journal),
          ChangeNotifierProvider<JournalLock>.value(value: jlock),
          ChangeNotifierProvider<DataStore>.value(value: store),
          Provider<BiometricService>.value(value: bio),
          Provider<SoundService>.value(value: SoundService(settings, silent: true)),
        ],
        child: MaterialApp(
          theme: buildTheme(const Color(0xFF4F6BED), Brightness.dark),
          builder: (c, child) => AuroraBackground(child: child!),
          home: child,
        ),
      );

  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
  }

  testWidgets('with fingerprint on, the lock screen unlocks by itself after a good touch', (t) async {
    tall(t);
    await settings.set('bioApp', true);
    await t.pumpWidget(app(const LockScreen()));
    await t.pump(const Duration(milliseconds: 300));
    expect(bio.prompts, 1); // it asked straight away
    expect(lock.locked, isFalse);
  });

  testWidgets('a failed touch leaves the PIN pad working, and the button asks again', (t) async {
    tall(t);
    bio.ok = false;
    await settings.set('bioApp', true);
    await t.pumpWidget(app(const LockScreen()));
    await t.pump(const Duration(milliseconds: 300));
    expect(lock.locked, isTrue);
    expect(find.text('Use fingerprint'), findsOneWidget);

    bio.ok = true;
    await t.tap(find.text('Use fingerprint'));
    await t.pump(const Duration(milliseconds: 300));
    expect(bio.prompts, 2);
    expect(lock.locked, isFalse);
  });

  testWidgets('a failed touch can still be backed up by the PIN', (t) async {
    tall(t);
    bio.ok = false;
    await settings.set('bioApp', true);
    await t.pumpWidget(app(const LockScreen()));
    await t.pump(const Duration(milliseconds: 300));
    for (final d in '2468'.split('')) {
      await t.tap(find.text(d).last);
      await t.pump(const Duration(milliseconds: 60));
    }
    await t.pump(const Duration(milliseconds: 400));
    expect(lock.locked, isFalse);
  });

  testWidgets('closing the prompt never reopens it by itself, so the PIN can be typed', (t) async {
    tall(t);
    bio.ok = false; // the user closes the prompt
    await settings.set('bioApp', true);
    await t.pumpWidget(app(const LockScreen()));
    await t.pump(const Duration(milliseconds: 300));
    expect(bio.prompts, 1);

    // closing the system prompt makes the app lose and regain focus, even go "paused" for a moment
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(milliseconds: 800));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 500));
    expect(bio.prompts, 1); // still just the first one: no loop

    // the PIN pad works
    for (final d in '2468'.split('')) {
      await t.tap(find.text(d).last);
      await t.pump(const Duration(milliseconds: 60));
    }
    await t.pump(const Duration(milliseconds: 400));
    expect(lock.locked, isFalse);
  });

  testWidgets('after really leaving the app for a while, the fingerprint is offered again', (t) async {
    tall(t);
    bio.ok = false;
    await settings.set('bioApp', true);
    await t.pumpWidget(app(const LockScreen()));
    await t.pump(const Duration(milliseconds: 300));
    expect(bio.prompts, 1);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(seconds: 6)); // away for six seconds
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 400));
    expect(bio.prompts, 2);
  });

  testWidgets('with fingerprint off, nothing is asked and there is no button', (t) async {
    tall(t);
    await t.pumpWidget(app(const LockScreen()));
    await t.pump(const Duration(milliseconds: 300));
    expect(bio.prompts, 0);
    expect(find.text('Use fingerprint'), findsNothing);
    expect(lock.locked, isTrue);
  });

  testWidgets('the journal opens with a fingerprint after the book opens', (t) async {
    tall(t);
    await settings.completeJournalSetup(mode: 'app');
    await settings.set('bioJournal', true);
    await t.pumpWidget(app(const JournalGate()));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('New entry'), findsNothing); // still the cover
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 1));
    expect(bio.prompts, greaterThanOrEqualTo(1));
    expect(jlock.isOpen, isTrue);
    expect(find.text('New entry'), findsOneWidget);
  });

  testWidgets('journal fingerprint failing falls back to the journal PIN', (t) async {
    tall(t);
    bio.ok = false;
    await settings.completeJournalSetup(mode: 'app');
    await settings.set('bioJournal', true);
    await t.pumpWidget(app(const JournalGate()));
    await t.pump(const Duration(seconds: 4));
    expect(jlock.isOpen, isFalse);
    expect(find.text('Use fingerprint'), findsOneWidget);
    expect(find.text('Enter your app PIN'), findsOneWidget);
  });

  testWidgets('Settings: turning fingerprint on needs a good touch; a bad one leaves it off', (t) async {
    tall(t);
    bio.ok = false;
    await t.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: BiometricTiles()))));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Unlock with fingerprint'));
    await t.pump(const Duration(milliseconds: 400));
    expect(settings.bioApp, isFalse);

    bio.ok = true;
    await t.tap(find.text('Unlock with fingerprint'));
    await t.pump(const Duration(milliseconds: 400));
    expect(settings.bioApp, isTrue);

    await t.tap(find.text('Open the journal with fingerprint'));
    await t.pump(const Duration(milliseconds: 400));
    expect(settings.bioJournal, isTrue);
  });

  testWidgets('Settings: switches are disabled when the phone has no fingerprint set up', (t) async {
    tall(t);
    bio.present = false;
    await t.pumpWidget(app(const Scaffold(body: SingleChildScrollView(child: BiometricTiles()))));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Add a fingerprint in your phone settings'), findsOneWidget);
    await t.tap(find.text('Unlock with fingerprint'));
    await t.pump(const Duration(milliseconds: 300));
    expect(settings.bioApp, isFalse);
    expect(bio.prompts, 0);
  });

  test('fingerprint settings stay on this device and are never synced', () {
    for (final k in ['bioApp', 'bioJournal', 'bioOffered']) {
      expect(SettingsService.syncedKeys.contains(k), isFalse);
    }
  });
}
