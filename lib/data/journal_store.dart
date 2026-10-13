import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/helpers.dart';
import 'data_store.dart';
import 'journal_models.dart';
import 'models.dart';

class JournalInsights {
  JournalInsights({
    required this.entries,
    required this.words,
    required this.currentStreak,
    required this.longestStreak,
    required this.photos,
    required this.videos,
    required this.audios,
    required this.places,
    required this.moodCounts,
    required this.writtenToday,
  });

  final int entries, words, currentStreak, longestStreak;
  final int photos, videos, audios, places;
  final List<int> moodCounts; // index 1..5
  final bool writtenToday;
}

class JournalStore extends ChangeNotifier {
  JournalStore(this.data) {
    data.onReload.add(load);
  }

  final DataStore data;
  List<JournalEntry> entries = [];

  Database get _db => data.db;

  Future<void> load() async {
    entries = (await _db.query('journal_entries', where: 'del=0')).map(JournalEntry.fromMap).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  Future<void> save(JournalEntry e) async {
    await data.put('journal_entries', e.toMap());
    final i = entries.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      entries[i] = e;
    } else {
      entries.add(e);
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  /// Deletes the entry and its attachments.
  Future<void> delete(JournalEntry e) async {
    await data.tombstone('journal_entries', 'id=?', [e.id]);
    entries.removeWhere((x) => x.id == e.id);
    for (final m in e.media) {
      await removeMedia(m);
    }
    notifyListeners();
  }

  /// Copies a picked/recorded file into the journal's hidden file folder.
  Future<JournalMedia> addMedia(String sourcePath, String kind, {String? name}) async {
    final f = await data.addJournalFile(sourcePath, name: name);
    return JournalMedia(fileId: f.id, kind: kind, name: f.name);
  }

  Future<void> removeMedia(JournalMedia m) async {
    final f = data.files.where((x) => x.id == m.fileId).firstOrNull;
    if (f != null) await data.deleteFile(f);
  }

  /// The stored file of an attachment, or null if its bytes are not on this device yet.
  File? fileOf(JournalMedia m) {
    final f = data.files.where((x) => x.id == m.fileId).firstOrNull;
    if (f == null || !data.hasLocalFile(f)) return null;
    return File(f.path);
  }

  VaultFile? recordOf(JournalMedia m) => data.files.where((x) => x.id == m.fileId).firstOrNull;

  // ---- queries ----
  List<JournalEntry> search(String q, {String filter = 'all'}) {
    final needle = q.trim().toLowerCase();
    return entries.where((e) {
      switch (filter) {
        case 'bookmarked':
          if (!e.bookmarked) return false;
        case 'photo':
        case 'video':
        case 'audio':
        case 'drawing':
          if (!e.has(filter)) return false;
        case 'places':
          if (!e.hasPlace) return false;
      }
      if (needle.isEmpty) return true;
      return '${e.title} ${e.body} ${e.place} ${e.tags.join(' ')}'.toLowerCase().contains(needle);
    }).toList();
  }

  List<JournalEntry> on(DateTime day) => entries.where((e) => dayOnly(e.date) == dayOnly(day)).toList();

  /// Entries written on today's date in earlier years ("On this day").
  List<JournalEntry> memories([DateTime? now]) {
    final t = now ?? DateTime.now();
    return entries.where((e) => e.date.month == t.month && e.date.day == t.day && e.date.year < t.year).toList();
  }

  bool get writtenToday => entries.any((e) => dayOnly(e.date) == dayOnly(DateTime.now()));

  JournalInsights insights() {
    final days = {for (final e in entries) dayOnly(e.date)};
    final today = dayOnly(DateTime.now());

    var current = 0;
    var d = days.contains(today) ? today : addDays(today, -1); // today not written yet keeps the streak alive
    while (days.contains(d)) {
      current++;
      d = addDays(d, -1);
    }
    var longest = 0, run = 0;
    final sorted = days.toList()..sort();
    for (var i = 0; i < sorted.length; i++) {
      run = (i > 0 && sorted[i].difference(sorted[i - 1]).inDays == 1) ? run + 1 : 1;
      if (run > longest) longest = run;
    }

    final moods = List.filled(6, 0);
    var photos = 0, videos = 0, audios = 0, places = 0, words = 0;
    for (final e in entries) {
      words += e.wordCount;
      if (e.mood > 0) moods[e.mood]++;
      if (e.hasPlace) places++;
      for (final m in e.media) {
        switch (m.kind) {
          case 'photo' || 'drawing':
            photos++;
          case 'video':
            videos++;
          case 'audio':
            audios++;
        }
      }
    }
    return JournalInsights(
      entries: entries.length,
      words: words,
      currentStreak: current,
      longestStreak: longest,
      photos: photos,
      videos: videos,
      audios: audios,
      places: places,
      moodCounts: moods,
      writtenToday: days.contains(today),
    );
  }
}
