import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taskme/data/data_store.dart';
import 'package:taskme/data/journal_models.dart';
import 'package:taskme/data/journal_store.dart';
import 'package:taskme/services/journal_lock.dart';
import 'package:taskme/services/settings_service.dart';

void main() {
  sqfliteFfiInit();

  late DataStore store;
  late JournalStore journal;
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    store = DataStore();
    await store.init(dir: await Directory.systemTemp.createTemp('myday_journal'), factory: databaseFactoryFfi);
    journal = JournalStore(store);
    await journal.load();
  });

  DateTime daysAgo(int n) => DateTime.now().subtract(Duration(days: n));

  test('streaks, words, filters, search and "on this day"', () async {
    await journal.save(JournalEntry(id: 'a', title: 'Today', body: 'one two three', date: daysAgo(0), mood: 4));
    await journal.save(JournalEntry(id: 'b', body: 'yesterday I walked', date: daysAgo(1), bookmarked: true, place: 'Beach'));
    await journal.save(JournalEntry(id: 'c', body: 'two days ago', date: daysAgo(2)));
    await journal.save(JournalEntry(id: 'd', body: 'a gap before this one', date: daysAgo(5)));
    await journal.save(JournalEntry(
        id: 'e', body: 'memory', date: DateTime(DateTime.now().year - 1, DateTime.now().month, DateTime.now().day)));

    final i = journal.insights();
    expect(i.entries, 5);
    expect(i.currentStreak, 3); // today, yesterday, two days ago
    expect(i.longestStreak, 3);
    expect(i.writtenToday, isTrue);
    expect(i.words, greaterThan(10));
    expect(i.moodCounts[4], 1);

    expect(journal.search('', filter: 'bookmarked').map((e) => e.id), ['b']);
    expect(journal.search('', filter: 'places').map((e) => e.id), ['b']);
    expect(journal.search('walked').map((e) => e.id), ['b']);
    expect(journal.memories().map((e) => e.id), ['e']);
  });

  test('the streak survives a day you have not written yet', () async {
    await journal.save(JournalEntry(id: 'y', body: 'yesterday', date: daysAgo(1)));
    await journal.save(JournalEntry(id: 'z', body: 'day before', date: daysAgo(2)));
    expect(journal.insights().currentStreak, 2);
    expect(journal.insights().writtenToday, isFalse);
  });

  test('entries, media and deletes survive a reload', () async {
    final f = File('${Directory.systemTemp.path}/pic_${DateTime.now().microsecondsSinceEpoch}.png')..writeAsBytesSync([1, 2, 3]);
    final m = await journal.addMedia(f.path, 'photo');
    await journal.save(JournalEntry(id: 'p', title: 'Pic', media: [m], tags: ['x', 'y'], lat: 9.9, lng: 76.2));
    await journal.load();
    final e = journal.entries.single;
    expect(e.tags, ['x', 'y']);
    expect(e.lat, 9.9);
    expect(journal.fileOf(e.media.single)!.readAsBytesSync(), [1, 2, 3]);
    await journal.delete(e);
    await journal.load();
    expect(journal.entries, isEmpty);
  });

  test('journal lock: app-PIN mode, separate-PIN mode and the grace period', () async {
    await settings.setPin('2468');
    final lock = JournalLock(settings);

    // same PIN as the app
    await settings.completeJournalSetup(mode: 'app');
    expect(lock.needsPin, isTrue);
    expect(lock.tryPin('0000'), isFalse);
    expect(lock.failedAttempts, 1);
    expect(lock.tryPin('2468'), isTrue);
    expect(lock.needsPin, isFalse); // inside the journal
    lock.leave();
    expect(lock.needsPin, isTrue); // grace 0 = every time

    // separate 6-digit PIN
    await settings.completeJournalSetup(mode: 'own', length: 6, pin: '135790');
    expect(settings.journalPinLen, 6);
    expect(lock.tryPin('2468'), isFalse); // the app PIN no longer works
    expect(lock.tryPin('135790'), isTrue);
    lock.leave();

    // grace period of 5 minutes: leaving and coming back does not ask again
    await settings.set('journalGrace', 5);
    expect(lock.tryPin('135790'), isTrue);
    lock.leave();
    expect(lock.needsPin, isFalse);
    // ...until the whole app locks
    lock.lockNow();
    expect(lock.needsPin, isTrue);
  });
}
