import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqf;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// A table that is synchronised between devices.
class SyncTable {
  const SyncTable(this.name, this.keys, {this.localOnly = const []});
  final String name;

  /// Primary-key columns.
  final List<String> keys;

  /// Columns that stay on this device and are never sent to the peer.
  final List<String> localOnly;
}

const syncTables = [
  SyncTable('tasks', ['id'], localOnly: ['notified']),
  SyncTable('notes', ['id']),
  SyncTable('files', ['id'], localOnly: ['path']),
  SyncTable('habits', ['id'], localOnly: ['lastNotified']),
  SyncTable('habit_logs', ['habit_id', 'day']),
  SyncTable('expense_cats', ['id']),
  SyncTable('expenses', ['id']),
  SyncTable('budgets', ['category']),
  SyncTable('recurring', ['id']),
  SyncTable('journal_entries', ['id']),
  SyncTable('kv', ['key']),
];

/// Owns the SQLite database and keeps everything in memory for the UI.
///
/// Every row carries three sync columns:
///  * `ts`  – when it was last edited (wall clock, used to settle conflicts)
///  * `del` – 1 when deleted (a tombstone, so deletes reach the other device)
///  * `sq`  – a per-device change counter (used to send only what is new)
class DataStore extends ChangeNotifier {
  static const dbVersion = 5;

  late Database _db;
  Database get db => _db;
  late Directory vaultDir;

  /// Other stores (habits, money) register here to reload after a restore or a sync.
  final List<Future<void> Function()> onReload = [];

  int _seq = 0;
  int nextSeq() => ++_seq;
  int get currentSeq => _seq;
  static int get nowTs => DateTime.now().millisecondsSinceEpoch;

  final _localChanges = StreamController<void>.broadcast();

  /// Fires after the user (not a sync) changes something.
  Stream<void> get localChanges => _localChanges.stream;

  final _uuid = const Uuid();
  List<Task> tasks = [];
  List<Note> notes = [];
  List<VaultFile> files = [];

  String newId() => _uuid.v4();

  /// Files shown in the Files tab (journal attachments are kept out of it).
  List<VaultFile> get visibleFiles => files.where((f) => f.folder != journalFolder).toList();

  static const journalFolder = '.journal';

  static const _sync =
      ", ts INTEGER NOT NULL DEFAULT 0, del INTEGER NOT NULL DEFAULT 0, sq INTEGER NOT NULL DEFAULT 0, src TEXT NOT NULL DEFAULT ''";

  static Future<void> createAllTables(Database db) async {
    await db.execute('''CREATE TABLE tasks(id TEXT PRIMARY KEY, title TEXT, description TEXT,
      due INTEGER, priority INTEGER, done INTEGER, repeat TEXT, remind INTEGER,
      notified INTEGER, tags TEXT, checklist TEXT, created INTEGER$_sync)''');
    await db.execute('''CREATE TABLE notes(id TEXT PRIMARY KEY, title TEXT, body TEXT,
      color INTEGER, pinned INTEGER, tags TEXT, created INTEGER, updated INTEGER$_sync)''');
    await db.execute('''CREATE TABLE files(id TEXT PRIMARY KEY, name TEXT, path TEXT,
      folder TEXT, size INTEGER, tags TEXT, created INTEGER$_sync)''');
    await createExtraTables(db);
    await createKv(db);
    await createJournal(db);
  }

  static Future<void> createJournal(Database db) => db.execute('''CREATE TABLE IF NOT EXISTS journal_entries(
      id TEXT PRIMARY KEY, title TEXT, body TEXT, date INTEGER, mood INTEGER, place TEXT, lat REAL, lng REAL,
      bookmarked INTEGER, tags TEXT, media TEXT, created INTEGER$_sync)''');

  /// The tables that existed when the sync columns were introduced (schema v3).
  static const _v3Tables = [
    'tasks', 'notes', 'files', 'habits', 'habit_logs', 'expense_cats', 'expenses', 'budgets', 'recurring',
  ];

  static Future<void> createKv(Database db) => db.execute(
      'CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT$_sync)');

  static const _defaultCats = [
    ['food', 'Food', 0, 3, 'expense'], ['transport', 'Transport', 1, 6, 'expense'],
    ['bills', 'Bills', 2, 8, 'expense'], ['shopping', 'Shopping', 3, 2, 'expense'],
    ['health', 'Health', 4, 5, 'expense'], ['fun', 'Fun', 5, 4, 'expense'],
    ['other', 'Other', 6, 9, 'expense'], ['salary', 'Salary', 7, 5, 'income'],
    ['gift', 'Gift', 8, 2, 'income'], ['other_income', 'Other income', 6, 1, 'income'],
  ];

  static Future<void> createExtraTables(Database db) async {
    await db.execute('''CREATE TABLE habits(id TEXT PRIMARY KEY, name TEXT, note TEXT, icon INTEGER,
      color INTEGER, type TEXT, target INTEGER, unit TEXT, freq TEXT, weekdays INTEGER,
      times INTEGER, remind TEXT, lastNotified TEXT, archived INTEGER, created INTEGER$_sync)''');
    await db.execute('''CREATE TABLE habit_logs(habit_id TEXT, day TEXT, value INTEGER$_sync,
      PRIMARY KEY(habit_id, day))''');
    await db.execute('''CREATE TABLE expense_cats(id TEXT PRIMARY KEY, name TEXT, icon INTEGER,
      color INTEGER, kind TEXT$_sync)''');
    await db.execute('''CREATE TABLE expenses(id TEXT PRIMARY KEY, amount REAL, kind TEXT,
      category TEXT, method TEXT, note TEXT, date INTEGER, fileId TEXT, recurringId TEXT,
      customName TEXT NOT NULL DEFAULT ''$_sync)''');
    await db.execute('CREATE TABLE budgets(category TEXT PRIMARY KEY, amount REAL$_sync)');
    await db.execute('''CREATE TABLE recurring(id TEXT PRIMARY KEY, amount REAL, kind TEXT,
      category TEXT, method TEXT, note TEXT, freq TEXT, next INTEGER, active INTEGER$_sync)''');
    for (final c in _defaultCats) {
      await db.insert('expense_cats',
          {'id': c[0], 'name': c[1], 'icon': c[2], 'color': c[3], 'kind': c[4]});
    }
  }

  /// Opens the database. [dir] and [factory] exist so tests can use a temp folder.
  Future<void> init({Directory? dir, DatabaseFactory? factory}) async {
    final mobile = Platform.isAndroid || Platform.isIOS;
    if (factory == null && !mobile) sqfliteFfiInit();
    final f = factory ?? (mobile ? sqf.databaseFactory : databaseFactoryFfi);
    final support = dir ?? await getApplicationSupportDirectory();
    await support.create(recursive: true);
    vaultDir = Directory(p.join(support.path, 'vault'));
    await vaultDir.create(recursive: true);
    final path = p.join(support.path, 'taskme.db');

    // Keep a copy of the database before a schema upgrade, just in case.
    if (await File(path).exists()) {
      try {
        final probe = await f.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
        final v = await probe.getVersion();
        await probe.close();
        if (v > 0 && v < dbVersion) await File(path).copy('$path.bak-v$v');
      } catch (_) {}
    }

    _db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onCreate: (db, _) => createAllTables(db),
        onUpgrade: (db, oldV, _) async {
          if (oldV < 2) await createExtraTables(db);
          if (oldV < 5) await createJournal(db);
          if (oldV < 4 && oldV >= 2) {
            await db.execute("ALTER TABLE expenses ADD COLUMN customName TEXT NOT NULL DEFAULT ''");
          }
          if (oldV < 3) {
            await createKv(db);
            final now = nowTs;
            for (final t in _v3Tables) {
              await db.execute('ALTER TABLE $t ADD COLUMN ts INTEGER NOT NULL DEFAULT 0');
              await db.execute('ALTER TABLE $t ADD COLUMN del INTEGER NOT NULL DEFAULT 0');
              await db.execute('ALTER TABLE $t ADD COLUMN sq INTEGER NOT NULL DEFAULT 0');
              await db.execute("ALTER TABLE $t ADD COLUMN src TEXT NOT NULL DEFAULT ''");
              // Existing data counts as "changed" so the first sync sends it.
              await db.execute('UPDATE $t SET ts=$now, sq=1');
            }
          }
        },
      ),
    );
    var max = 0;
    for (final t in syncTables) {
      final r = await _db.rawQuery('SELECT MAX(sq) AS m FROM ${t.name}');
      final m = (r.first['m'] as int?) ?? 0;
      if (m > max) max = m;
    }
    _seq = max;
    await reload();
  }

  /// Lets the UI repaint after something changed outside the store (e.g. a file arrived).
  void refresh() => notifyListeners();

  Future<void> reload() async {
    tasks = (await _db.query('tasks', where: 'del=0')).map(Task.fromMap).toList();
    notes = (await _db.query('notes', where: 'del=0')).map(Note.fromMap).toList();
    files = (await _db.query('files', where: 'del=0')).map(VaultFile.fromMap).toList();
    for (final cb in onReload) {
      await cb();
    }
    notifyListeners();
  }

  // ---- low-level writes that keep the sync columns right ----

  /// Inserts or replaces a row, stamping it as changed now.
  Future<void> put(String table, Map<String, Object?> row) async {
    await _db.insert(table, {...row, 'ts': nowTs, 'del': 0, 'sq': nextSeq(), 'src': ''},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _localChanges.add(null);
  }

  /// Marks matching rows as deleted (a tombstone is kept so the delete syncs).
  Future<void> tombstone(String table, String where, List<Object?> args) async {
    await _db.update(table, {'del': 1, 'ts': nowTs, 'sq': nextSeq(), 'src': ''},
        where: '($where) AND del=0', whereArgs: args);
    _localChanges.add(null);
  }

  /// Updates columns of matching rows and stamps them as changed now.
  Future<void> touch(String table, Map<String, Object?> values, String where, List<Object?> args) async {
    await _db.update(table, {...values, 'ts': nowTs, 'sq': nextSeq(), 'src': ''},
        where: '($where) AND del=0', whereArgs: args);
    _localChanges.add(null);
  }

  // ---- tasks ----
  Future<void> saveTask(Task t) async {
    await put('tasks', t.toMap());
    final i = tasks.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      tasks[i] = t;
    } else {
      tasks.add(t);
    }
    notifyListeners();
  }

  Future<void> deleteTask(Task t) async {
    await tombstone('tasks', 'id=?', [t.id]);
    tasks.removeWhere((e) => e.id == t.id);
    notifyListeners();
  }

  /// Records that this device already showed the reminder. Local only, not synced.
  Future<void> markTaskNotified(Task t) async {
    t.notified = true;
    await _db.update('tasks', {'notified': 1}, where: 'id=?', whereArgs: [t.id]);
  }

  /// Completes a task; repeating tasks roll forward instead of finishing.
  Future<void> toggleDone(Task t) async {
    if (!t.done && t.repeat != 'none' && t.due != null) {
      var d = t.due!;
      final now = DateTime.now();
      do {
        d = switch (t.repeat) {
          'daily' => d.add(const Duration(days: 1)),
          'weekly' => d.add(const Duration(days: 7)),
          _ => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
        };
      } while (d.isBefore(now));
      t.due = d;
      t.notified = false;
      for (final c in t.checklist) {
        c.done = false;
      }
    } else {
      t.done = !t.done;
    }
    await saveTask(t);
  }

  Future<void> snooze(Task t, Duration d) async {
    t.due = DateTime.now().add(d);
    t.notified = false;
    await saveTask(t);
  }

  // ---- notes ----
  Future<void> saveNote(Note n) async {
    n.updated = DateTime.now();
    await put('notes', n.toMap());
    final i = notes.indexWhere((e) => e.id == n.id);
    if (i >= 0) {
      notes[i] = n;
    } else {
      notes.add(n);
    }
    notifyListeners();
  }

  Future<void> deleteNote(Note n) async {
    await tombstone('notes', 'id=?', [n.id]);
    notes.removeWhere((e) => e.id == n.id);
    notifyListeners();
  }

  // ---- files ----
  String localPathFor(String id, String name) => p.join(vaultDir.path, '${id}_$name');

  /// Deletes the stored bytes of a file (its record stays as a tombstone).
  Future<void> removeLocalBytes(VaultFile f) async {
    try {
      await File(localPathFor(f.id, f.name)).delete();
    } catch (_) {}
  }

  /// True when the file's bytes are on this device (they may still be on the other one).
  bool hasLocalFile(VaultFile f) => File(f.path).existsSync();

  Future<void> addFiles(List<String> sourcePaths, {String folder = ''}) async {
    for (final src in sourcePaths) {
      final id = newId();
      final name = p.basename(src);
      final dest = localPathFor(id, name);
      await File(src).copy(dest);
      final f = VaultFile(
          id: id, name: name, path: dest, folder: folder, size: await File(dest).length());
      await put('files', f.toMap());
      files.add(f);
    }
    notifyListeners();
  }

  /// Stores a journal attachment (hidden from the Files tab; still synced like a file).
  Future<VaultFile> addJournalFile(String sourcePath, {String? name}) async {
    final id = newId();
    final fileName = name ?? p.basename(sourcePath);
    final dest = localPathFor(id, fileName);
    await File(sourcePath).copy(dest);
    final f = VaultFile(id: id, name: fileName, path: dest, folder: journalFolder, size: await File(dest).length());
    await put('files', f.toMap());
    files.add(f);
    return f;
  }

  Future<void> saveFileMeta(VaultFile f) async {
    await put('files', f.toMap());
    notifyListeners();
  }

  Future<void> deleteFile(VaultFile f) async {
    await tombstone('files', 'id=?', [f.id]);
    try {
      await File(f.path).delete();
    } catch (_) {}
    files.removeWhere((e) => e.id == f.id);
    notifyListeners();
  }

  // ---- backup / restore ----
  /// Backed-up tables (everything except the synced-settings table).
  static final _backupTables = syncTables.where((t) => t.name != 'kv').map((t) => t.name).toList();

  /// Writes a single .zip containing all data, files and the given settings.
  Future<void> exportBackup(String zipPath, Map<String, dynamic> settings) async {
    final enc = ZipFileEncoder()..create(zipPath);
    final tables = {
      for (final t in _backupTables) t: await _db.query(t, where: 'del=0'),
    };
    final meta = jsonEncode({'version': 2, 'settings': settings, 'tables': tables});
    enc.addArchiveFile(ArchiveFile.bytes('data.json', utf8.encode(meta)));
    for (final f in files) {
      if (await File(f.path).exists()) {
        await enc.addFile(File(f.path), 'vault/${p.basename(f.path)}');
      }
    }
    await enc.close();
  }

  /// Replaces everything with the backup's contents. Returns the saved settings.
  /// Existing rows are tombstoned first so a paired device mirrors the restore.
  Future<Map<String, dynamic>> importBackup(String zipPath) async {
    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final dataEntry = archive.findFile('data.json');
    if (dataEntry == null) throw const FormatException('Not a MyDay backup');
    final meta = jsonDecode(utf8.decode(dataEntry.content as List<int>)) as Map<String, dynamic>;

    // Version 1 backups kept tasks/notes/files at the top level and the rest under "extra".
    final Map<String, List> tables;
    if (meta['tables'] != null) {
      tables = {
        for (final e in (meta['tables'] as Map).entries) e.key as String: e.value as List,
      };
    } else {
      final extra = (meta['extra'] as Map?) ?? {};
      tables = {
        'tasks': meta['tasks'] as List? ?? [],
        'notes': meta['notes'] as List? ?? [],
        'files': meta['files'] as List? ?? [],
        for (final e in extra.entries) e.key as String: e.value as List,
      };
    }

    for (final t in _backupTables) {
      await _db.update(t, {'del': 1, 'ts': nowTs, 'sq': nextSeq(), 'src': ''}, where: 'del=0');
    }
    if (await vaultDir.exists()) await vaultDir.delete(recursive: true);
    await vaultDir.create(recursive: true);

    for (final t in _backupTables) {
      for (final raw in tables[t] ?? const []) {
        final m = Map<String, Object?>.from(raw as Map);
        if (t == 'files') {
          final stored = p.basename(m['path'] as String);
          final entry = archive.findFile('vault/$stored');
          final dest = p.join(vaultDir.path, stored);
          if (entry != null) await File(dest).writeAsBytes(entry.content as List<int>);
          m['path'] = dest;
        }
        await _db.insert(t, {...m, 'ts': nowTs + 1, 'del': 0, 'sq': nextSeq(), 'src': ''},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    // A backup from before habits/money existed has no categories: bring the defaults back.
    final cats = await _db.query('expense_cats', where: 'del=0');
    if (cats.isEmpty) {
      for (final c in _defaultCats) {
        await _db.insert(
            'expense_cats',
            {'id': c[0], 'name': c[1], 'icon': c[2], 'color': c[3], 'kind': c[4],
             'ts': nowTs + 1, 'del': 0, 'sq': nextSeq(), 'src': ''},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    _localChanges.add(null);
    await reload();
    return Map<String, dynamic>.from(meta['settings'] as Map);
  }

  @override
  void dispose() {
    _localChanges.close();
    super.dispose();
  }
}
