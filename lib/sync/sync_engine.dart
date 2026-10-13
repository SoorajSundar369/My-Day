import 'package:sqflite_common/sqlite_api.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../services/settings_service.dart';

typedef Rows = Map<String, List<Map<String, Object?>>>;

class ApplyResult {
  ApplyResult(this.applied, this.tables, this.newFiles);
  final int applied;
  final Set<String> tables;

  /// File records that arrived without their bytes.
  final List<VaultFile> newFiles;
}

/// Database side of syncing: pick what changed, merge what arrived.
///
/// Conflict rule: for the same record the newest edit wins. Deletions are
/// records too (tombstones), so a delete beats an older edit and never "comes back".
class SyncEngine {
  SyncEngine(this.store, this.settings);

  final DataStore store;
  final SettingsService settings;
  Database get _db => store.db;
  final _colCache = <String, Set<String>>{};

  /// Everything changed after change-counter [since], except what [peerId] itself sent us.
  Future<Rows> rowsSince(int since, String peerId) async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final t in syncTables) {
      final rows = await _db.query(t.name, where: 'sq > ? AND src != ?', whereArgs: [since, peerId]);
      if (rows.isEmpty) continue;
      out[t.name] = [
        for (final r in rows)
          {
            for (final e in r.entries)
              if (e.key != 'sq' && e.key != 'src' && !t.localOnly.contains(e.key)) e.key: e.value,
          },
      ];
    }
    return out;
  }

  /// Merges rows from the peer. [clockOffset] = peer clock minus our clock (ms).
  Future<ApplyResult> applyRows(Rows incoming, {required String peerId, required int clockOffset}) async {
    var applied = 0;
    final touched = <String>{};
    final newFiles = <VaultFile>[];
    final kvChanges = <Map<String, Object?>>[];
    final now = DataStore.nowTs;

    await _db.transaction((txn) async {
      for (final spec in syncTables) {
        for (final raw in incoming[spec.name] ?? const <Map<String, Object?>>[]) {
          final row = Map<String, Object?>.from(raw);
          final inTs = (row['ts'] as int) - clockOffset;
          final where = spec.keys.map((k) => '$k=?').join(' AND ');
          final args = spec.keys.map((k) => row[k]).toList();
          final local = await txn.query(spec.name, where: where, whereArgs: args, limit: 1);
          final localRow = local.isEmpty ? null : local.first;
          if (localRow != null && inTs <= (localRow['ts'] as int)) continue; // ours is as new or newer

          // Ignore columns this version of the app does not have (other device on an older/newer build).
          final cols = _colCache[spec.name] ??= {
            for (final r in await txn.rawQuery('PRAGMA table_info(${spec.name})')) r['name'] as String,
          };
          row.removeWhere((k, _) => !cols.contains(k));

          row['ts'] = inTs;
          row['sq'] = store.nextSeq();
          row['src'] = peerId;
          final deleted = row['del'] == 1;

          // Columns that never leave a device keep their local value.
          switch (spec.name) {
            case 'tasks':
              final dueSame = localRow != null && localRow['due'] == row['due'];
              final due = row['due'] as int?;
              final past = due != null && due < now;
              row['notified'] = (dueSame ? localRow['notified'] : (past ? 1 : 0)) ?? 0;
            case 'habits':
              row['lastNotified'] = localRow?['lastNotified'] ?? '';
            case 'files':
              row['path'] = store.localPathFor(row['id'] as String, row['name'] as String);
          }

          await txn.insert(spec.name, row, conflictAlgorithm: ConflictAlgorithm.replace);
          applied++;
          touched.add(spec.name);
          if (spec.name == 'kv') kvChanges.add(row);
          if (spec.name == 'files') {
            final vf = VaultFile.fromMap(row);
            if (deleted) {
              await store.removeLocalBytes(vf);
            } else {
              newFiles.add(vf);
            }
          }
        }
      }
    });

    // "setupDone" goes last so the app only switches to the lock screen once the PIN is in place.
    kvChanges.sort((a, b) => (a['key'] == 'setupDone' ? 1 : 0).compareTo(b['key'] == 'setupDone' ? 1 : 0));
    for (final r in kvChanges) {
      if (r['del'] != 1) await settings.applyRemote(r['key'] as String, '${r['value']}');
    }
    return ApplyResult(applied, touched, newFiles.where((f) => !store.hasLocalFile(f)).toList());
  }

  /// Shares everything that makes this device "set up" (name, PIN, security question, journal lock)
  /// so a brand-new device can skip setup. Used when the other device has just been installed.
  Future<void> seedIdentity() async {
    for (final k in SettingsService.identityKeys) {
      final v = settings.syncedValue(k);
      if (v != null) await store.put('kv', {'key': k, 'value': v});
    }
  }

  /// Puts the current value of every synced setting in the sync table (once, on the desktop).
  Future<void> seedSettings() async {
    for (final k in SettingsService.syncedKeys) {
      if (SettingsService.securityKeys.contains(k)) continue; // PIN & co. are only shared with brand-new devices
      final v = settings.syncedValue(k);
      if (v == null) continue;
      final existing = await _db.query('kv', where: 'key=?', whereArgs: [k], limit: 1);
      if (existing.isEmpty) await store.put('kv', {'key': k, 'value': v});
    }
  }
}
