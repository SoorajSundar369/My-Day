import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taskme/data/data_store.dart';
import 'package:taskme/data/habit_models.dart';
import 'package:taskme/data/habit_store.dart';
import 'package:taskme/data/journal_models.dart';
import 'package:taskme/data/journal_store.dart';
import 'package:taskme/data/models.dart';
import 'package:taskme/data/money_store.dart';
import 'package:taskme/services/settings_service.dart';
import 'package:taskme/sync/sync_cipher.dart';
import 'package:taskme/sync/sync_engine.dart';
import 'package:taskme/sync/sync_net.dart';
import 'package:taskme/sync/sync_session.dart';

class MemChannel implements SyncChannel {
  MemChannel(this._in, this._out);
  final StreamController<Uint8List> _in;
  final StreamController<Uint8List> _out;
  @override
  Stream<Uint8List> get incoming => _in.stream;
  @override
  void send(Uint8List data) {
    if (!_out.isClosed) _out.add(data);
  }

  @override
  Future<void> close() async {
    if (!_out.isClosed) await _out.close();
  }
}

class MemState implements SyncStateStore {
  final map = <String, int>{};
  @override
  Future<int> since(String peerId) async => map[peerId] ?? 0;
  @override
  Future<void> setSince(String peerId, int v) async => map[peerId] = v;
}

class Peer {
  Peer(this.id);
  final String id;
  late Directory dir;
  late DataStore store;
  late SettingsService settings;
  late HabitStore habits;
  late MoneyStore money;
  late JournalStore journal;
  late SyncEngine engine;
  final state = MemState();
  SyncSession? session;
  final events = StreamController<SyncEvent>.broadcast();

  Future<void> init() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    dir = await Directory.systemTemp.createTemp('myday_sync_$id');
    store = DataStore();
    await store.init(dir: dir, factory: databaseFactoryFfi);
    habits = HabitStore(store, settings);
    money = MoneyStore(store, settings);
    await habits.load();
    await money.load();
    journal = JournalStore(store);
    await journal.load();
    engine = SyncEngine(store, settings);
  }
}

/// Connects two peers and waits for the first full sync on both sides.
Future<void> connect(Peer a, Peer b, {int autoFileBytes = 10 * 1024 * 1024}) async {
  final key = SyncCipher.generateKey();
  final ab = StreamController<Uint8List>();
  final ba = StreamController<Uint8List>();
  a.session = SyncSession(
    channel: MemChannel(ba, ab),
    cipher: SyncCipher.fromBase64(key),
    engine: a.engine,
    state: a.state,
    deviceId: a.id,
    deviceName: a.id,
    autoFileBytes: autoFileBytes,
    onEvent: a.events.add,
    isFresh: () => !a.settings.setupDone,
    onPeerFresh: a.engine.seedIdentity,
  );
  b.session = SyncSession(
    channel: MemChannel(ab, ba),
    cipher: SyncCipher.fromBase64(key),
    engine: b.engine,
    state: b.state,
    deviceId: b.id,
    deviceName: b.id,
    autoFileBytes: autoFileBytes,
    onEvent: b.events.add,
    isFresh: () => !b.settings.setupDone,
    onPeerFresh: b.engine.seedIdentity,
  );
  final doneA = a.events.stream.firstWhere((e) => e is SyncedEvent);
  final doneB = b.events.stream.firstWhere((e) => e is SyncedEvent);
  a.session!.start();
  b.session!.start();
  await Future.wait([doneA, doneB]).timeout(const Duration(seconds: 10));
}

/// Makes [from] announce a change and waits until [to] has synced it.
Future<SyncedEvent> push(Peer from, Peer to) async {
  final done = to.events.stream.firstWhere((e) => e is SyncedEvent).then((e) => e as SyncedEvent);
  from.session!.announceChanged();
  return done.timeout(const Duration(seconds: 10));
}

void main() {
  sqfliteFfiInit();
  late Peer desktop;
  late Peer phone;

  setUp(() async {
    desktop = Peer('desktop');
    phone = Peer('phone');
    await desktop.init();
    await phone.init();
  });

  tearDown(() async {
    await desktop.session?.close();
    await phone.session?.close();
  });

  test('cipher round-trips and rejects wrong key or tampering', () async {
    final c = SyncCipher.fromBase64(SyncCipher.generateKey());
    final enc = await c.encrypt([1, 2, 3, 4]);
    expect(await c.decrypt(enc), [1, 2, 3, 4]);
    expect(await SyncCipher.fromBase64(SyncCipher.generateKey()).decrypt(enc), isNull);
    enc[enc.length - 1] ^= 0xFF;
    expect(await c.decrypt(enc), isNull);
  });

  test('first sync copies everything from desktop to an empty phone', () async {
    await desktop.store.saveTask(Task(id: 't1', title: 'Pay bill', due: DateTime.now().add(const Duration(days: 1)), remind: true));
    await desktop.store.saveNote(Note(id: 'n1', title: 'Idea', body: 'Hello'));
    await desktop.habits.save(Habit(id: 'h1', name: 'Read'));
    await desktop.habits.setValue(desktop.habits.habits.first, DateTime(2026, 10, 1), 1);
    await desktop.money.save(Expense(id: 'e1', amount: 250, category: 'food'));
    await desktop.money.setBudget('', 30000);

    await connect(desktop, phone);

    expect(phone.store.tasks.map((t) => t.title), ['Pay bill']);
    expect(phone.store.notes.single.body, 'Hello');
    expect(phone.habits.habits.single.name, 'Read');
    expect(phone.habits.valueOn(phone.habits.habits.single, DateTime(2026, 10, 1)), 1);
    expect(phone.money.expenses.single.amount, 250);
    expect(phone.money.budgets[''], 30000);
  });

  test('changes made on either device reach the other, and nothing echoes back', () async {
    await connect(desktop, phone);

    await phone.store.saveTask(Task(id: 'p1', title: 'From phone'));
    final ev = await push(phone, desktop);
    expect(ev.applied, 1);
    expect(desktop.store.tasks.single.title, 'From phone');

    await desktop.store.saveNote(Note(id: 'd1', title: 'From desktop'));
    await push(desktop, phone);
    expect(phone.store.notes.single.title, 'From desktop');

    // the phone's own task must not bounce back to the phone as a "change"
    final again = await push(desktop, phone);
    expect(again.applied, 0);
  });

  test('conflict: the newest edit wins on both devices', () async {
    await desktop.store.saveTask(Task(id: 'c1', title: 'Original'));
    await connect(desktop, phone);

    final dt = desktop.store.tasks.single..title = 'Desktop edit';
    await desktop.store.saveTask(dt);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final pt = phone.store.tasks.single..title = 'Phone edit (later)';
    await phone.store.saveTask(pt);

    await push(desktop, phone);
    await push(phone, desktop);
    await push(desktop, phone);

    expect(desktop.store.tasks.single.title, 'Phone edit (later)');
    expect(phone.store.tasks.single.title, 'Phone edit (later)');
  });

  test('a delete syncs and the item does not come back', () async {
    await desktop.store.saveTask(Task(id: 'x1', title: 'Temp'));
    await connect(desktop, phone);
    expect(phone.store.tasks, hasLength(1));

    await phone.store.deleteTask(phone.store.tasks.single);
    await push(phone, desktop);
    expect(desktop.store.tasks, isEmpty);

    // later activity must not resurrect it
    await desktop.store.saveNote(Note(id: 'n', title: 'later'));
    await push(desktop, phone);
    expect(phone.store.tasks, isEmpty);
    expect(desktop.store.tasks, isEmpty);
  });

  test('device-only flags stay local; old reminders do not fire after a first sync', () async {
    final old = Task(id: 'o1', title: 'Old', due: DateTime.now().subtract(const Duration(days: 3)), remind: true);
    await desktop.store.saveTask(old);
    await connect(desktop, phone);
    // already past: marked as notified on the phone so it does not toast
    expect(phone.store.tasks.single.notified, isTrue);

    final future = Task(id: 'f1', title: 'Soon', due: DateTime.now().add(const Duration(hours: 2)), remind: true);
    await desktop.store.saveTask(future);
    await push(desktop, phone);
    expect(phone.store.tasks.firstWhere((t) => t.id == 'f1').notified, isFalse);

    // desktop shows its reminder: local only, must not change anything on the phone
    await desktop.store.markTaskNotified(desktop.store.tasks.firstWhere((t) => t.id == 'f1'));
    desktop.session!.announceChanged();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(phone.store.tasks.firstWhere((t) => t.id == 'f1').notified, isFalse);
  });

  test('settings sync both ways, security settings do not', () async {
    await desktop.settings.saveProfile(name: 'Sooraj', nickname: 'Sj');
    desktop.settings.onSyncedChange = (k, v) => desktop.store.put('kv', {'key': k, 'value': v});
    await desktop.engine.seedSettings();
    await desktop.settings.set('currency', r'$');
    await connect(desktop, phone);
    expect(phone.settings.name, 'Sooraj');
    expect(phone.settings.nickname, 'Sj');
    expect(phone.settings.currency, r'$');
    expect(phone.settings.themeMode.index, 0);
  });

  test('small files copy automatically, big ones wait for approval', () async {
    final small = File('${desktop.dir.path}/small.txt')..writeAsStringSync('hello file');
    final big = File('${desktop.dir.path}/big.bin')..writeAsBytesSync(List.filled(5000, 7));
    await desktop.store.addFiles([small.path, big.path]);

    final ask = phone.events.stream.firstWhere((e) => e is FilesNeedApproval);
    final got = phone.events.stream.firstWhere((e) => e is FileReceived);
    await connect(desktop, phone, autoFileBytes: 1000);

    final received = await got.timeout(const Duration(seconds: 10)) as FileReceived;
    expect(received.file.name, 'small.txt');
    expect(File(phone.store.files.firstWhere((f) => f.name == 'small.txt').path).readAsStringSync(), 'hello file');

    final approval = await ask.timeout(const Duration(seconds: 10)) as FilesNeedApproval;
    expect(approval.files.single.name, 'big.bin');
    expect(phone.store.hasLocalFile(approval.files.single), isFalse);

    // user taps "download"
    final bigDone = phone.events.stream.firstWhere((e) => e is FileReceived && e.file.name == 'big.bin');
    phone.session!.requestFile(approval.files.single.id);
    await bigDone.timeout(const Duration(seconds: 10));
    expect(File(phone.store.files.firstWhere((f) => f.name == 'big.bin').path).lengthSync(), 5000);
  });

  test('a second sync after reconnecting only sends what is new', () async {
    await desktop.store.saveNote(Note(id: 'a', title: 'one'));
    await connect(desktop, phone);
    await desktop.session!.close();
    await phone.session!.close();

    await desktop.store.saveNote(Note(id: 'b', title: 'two'));
    final done = phone.events.stream.firstWhere((e) => e is SyncedEvent);
    await connect(desktop, phone);
    final ev = await done as SyncedEvent;
    expect(ev.applied, 1);
    expect(phone.store.notes, hasLength(2));
  });

  test('recurring entries created on both devices do not duplicate', () async {
    await desktop.money.saveRecurring(Recurring(
        id: 'r1', amount: 500, category: 'bills', next: DateTime.now().subtract(const Duration(hours: 1))));
    await connect(desktop, phone);
    await phone.money.processRecurring();
    await desktop.money.processRecurring();
    await push(phone, desktop);
    await push(desktop, phone);
    expect(desktop.money.expenses.where((e) => e.recurringId == 'r1' || e.id.startsWith('rec-r1')), hasLength(1));
    expect(phone.money.expenses.where((e) => e.id.startsWith('rec-r1')), hasLength(1));
  });

  test('over a real WebSocket: right key syncs, wrong key is rejected', () async {
    await desktop.store.saveTask(Task(id: 'w1', title: 'Over the wire'));
    final key = SyncCipher.generateKey();

    final server = SyncServer(
      deviceId: 'desktop',
      onSocket: (ws, from) {
        final ch = WsChannel<SyncCipher>(ws, gate: (first) async {
          final c = SyncCipher.fromBase64(key);
          return await c.decrypt(first) != null ? c : null;
        });
        ch.gateResult.then((c) {
          if (c == null) return;
          desktop.session = SyncSession(
              channel: ch, cipher: c, engine: desktop.engine, state: desktop.state,
              deviceId: 'desktop', deviceName: 'desktop', onEvent: desktop.events.add)
            ..start();
        });
      },
    );
    await server.start();
    addTearDown(server.stop);

    // intruder with the wrong key: connection is dropped, desktop never starts a session
    final badWs = await connectSocket('127.0.0.1', server.port);
    final bad = SyncSession(
        channel: WsChannel<void>(badWs), cipher: SyncCipher.fromBase64(SyncCipher.generateKey()),
        engine: phone.engine, state: MemState(), deviceId: 'intruder', deviceName: 'x');
    final closed = Completer<void>();
    bad.onEvent = (e) {
      if (e is SessionClosed && !closed.isCompleted) closed.complete();
    };
    bad.start();
    await closed.future.timeout(const Duration(seconds: 10));
    expect(desktop.session, isNull);

    // the real phone
    final ws = await connectSocket('127.0.0.1', server.port);
    final doneP = phone.events.stream.firstWhere((e) => e is SyncedEvent);
    phone.session = SyncSession(
        channel: WsChannel<void>(ws), cipher: SyncCipher.fromBase64(key), engine: phone.engine,
        state: phone.state, deviceId: 'phone', deviceName: 'phone', onEvent: phone.events.add)
      ..start();
    await doneP.timeout(const Duration(seconds: 10));
    expect(phone.store.tasks.single.title, 'Over the wire');

    // and live changes flow while connected
    await phone.store.saveNote(Note(id: 'live', title: 'Live note'));
    await push(phone, desktop);
    expect(desktop.store.notes.single.title, 'Live note');
  });

  test('the phone can find the desktop by broadcast', () async {
    final server = SyncServer(deviceId: 'desk-123', onSocket: (ws, from) => ws.close());
    await server.start();
    addTearDown(server.stop);
    final found = await discoverDesktop('desk-123');
    expect(found, isNotNull);
    expect(found!.$2, server.port);
    expect(await discoverDesktop('someone-else', timeout: const Duration(milliseconds: 800)), isNull);
  });

  test('journal entries and their photos sync, and stay out of the Files tab', () async {
    final photo = File('${desktop.dir.path}/sunset.jpg')..writeAsBytesSync(List.filled(2000, 9));
    final media = await desktop.journal.addMedia(photo.path, 'photo');
    await desktop.journal.save(JournalEntry(
        id: 'j1', title: 'A good day', body: 'Walked by the **sea**', mood: 5, place: 'Kochi', media: [media], bookmarked: true));

    final gotFile = phone.events.stream.firstWhere((e) => e is FileReceived);
    await connect(desktop, phone);
    await gotFile.timeout(const Duration(seconds: 10));

    final e = phone.journal.entries.single;
    expect(e.title, 'A good day');
    expect(e.mood, 5);
    expect(e.bookmarked, isTrue);
    expect(e.place, 'Kochi');
    expect(phone.journal.fileOf(e.media.single), isNotNull); // the photo bytes arrived
    expect(phone.journal.fileOf(e.media.single)!.lengthSync(), 2000);
    expect(phone.store.visibleFiles, isEmpty); // journal photos are hidden from Files
    expect(phone.store.files, hasLength(1));

    // edit on the phone, delete on the desktop
    final pe = phone.journal.entries.single..body = 'Edited on the phone';
    await phone.journal.save(pe);
    await push(phone, desktop);
    expect(desktop.journal.entries.single.body, 'Edited on the phone');

    await desktop.journal.delete(desktop.journal.entries.single);
    await push(desktop, phone);
    expect(phone.journal.entries, isEmpty);
    expect(phone.store.files.where((f) => f.folder == '.journal'), isEmpty); // attachment removed too
  });

  test('lock and PIN settings follow the user to the other device', () async {
    await desktop.settings.setPin('1234');
    await desktop.settings.setSecurity(question: 'First pet?', answer: 'Rex', hint: 'dog');
    await desktop.settings.completeJournalSetup(mode: 'own', length: 6, pin: '123456');
    await desktop.settings.set('journalGrace', 30);
    // what the sync service does when the other device is brand new: share the identity settings
    for (final k in SettingsService.syncedKeys) {
      final v = desktop.settings.syncedValue(k);
      if (v != null) await desktop.store.put('kv', {'key': k, 'value': v});
    }
    await connect(desktop, phone);
    expect(phone.settings.checkPin('1234'), isTrue);
    expect(phone.settings.verifyAnswer('rex'), isTrue);
    expect(phone.settings.journalMode, 'own');
    expect(phone.settings.journalPinLen, 6);
    expect(phone.settings.checkJournalPin('123456'), isTrue);
    expect(phone.settings.checkJournalPin('000000'), isFalse);
    expect(phone.settings.journalGraceMinutes, 30);
    expect(phone.settings.journalSetupDone, isTrue);
  });

  test('a brand-new phone inherits name, PIN, security question and journal lock from the computer', () async {
    await desktop.settings.saveProfile(name: 'Sooraj', nickname: 'Sj');
    await desktop.settings.setPin('4321');
    await desktop.settings.setSecurity(question: 'First car?', answer: 'Alto', hint: 'small');
    await desktop.settings.completeSetup();
    await desktop.settings.completeJournalSetup(mode: 'own', length: 6, pin: '246810');
    await desktop.store.saveTask(Task(id: 't-old', title: 'An existing task'));
    expect(phone.settings.setupDone, isFalse);

    await connect(desktop, phone);

    expect(phone.settings.setupDone, isTrue); // no setup screens needed on the phone
    expect(phone.settings.name, 'Sooraj');
    expect(phone.settings.nickname, 'Sj');
    expect(phone.settings.checkPin('4321'), isTrue); // the same PIN opens it
    expect(phone.settings.checkPin('0000'), isFalse);
    expect(phone.settings.verifyAnswer('alto'), isTrue);
    expect(phone.settings.journalSetupDone, isTrue);
    expect(phone.settings.checkJournalPin('246810'), isTrue);
    expect(phone.store.tasks.single.title, 'An existing task');
  });

  test('a brand-new computer inherits everything from a phone that was set up first', () async {
    await phone.settings.saveProfile(name: 'Asha', nickname: 'Ash');
    await phone.settings.setPin('9876');
    await phone.settings.setSecurity(question: 'Pet?', answer: 'Tom', hint: 'cat');
    await phone.settings.completeSetup();
    await phone.settings.completeJournalSetup(mode: 'app');
    await phone.store.saveNote(Note(id: 'n-phone', title: 'Written on the phone first'));
    await phone.journal.save(JournalEntry(id: 'j-phone', title: 'Dear diary', body: 'Hello'));

    await connect(phone, desktop); // the phone is "a", the fresh computer is "b"

    expect(desktop.settings.setupDone, isTrue);
    expect(desktop.settings.name, 'Asha');
    expect(desktop.settings.checkPin('9876'), isTrue);
    expect(desktop.settings.journalMode, 'app');
    expect(desktop.store.notes.single.title, 'Written on the phone first');
    expect(desktop.journal.entries.single.title, 'Dear diary');
  });

  test('two devices that are both already set up keep their own PINs on first sync', () async {
    await desktop.settings.setPin('1111');
    await desktop.settings.completeSetup();
    await phone.settings.setPin('2222');
    await phone.settings.completeSetup();
    // what the real app does when the computer's sync server starts
    await desktop.engine.seedSettings();
    await phone.engine.seedSettings();
    await connect(desktop, phone);
    expect(desktop.settings.checkPin('1111'), isTrue);
    expect(phone.settings.checkPin('2222'), isTrue); // nobody is locked out by a surprise PIN change
  });
}
