import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/helpers.dart';
import '../services/settings_service.dart';
import 'data_store.dart';
import 'habit_models.dart';

/// Everything derived from a habit's history, shown on its detail screen.
class HabitStats {
  HabitStats({
    required this.current,
    required this.best,
    required this.totalDone,
    required this.unit,
    required this.rateWeek,
    required this.rateMonth,
    required this.rateYear,
    required this.rateAll,
    required this.weekdayCounts,
    required this.weeklyBars,
  });

  final int current;
  final int best;
  final int totalDone;
  final String unit; // days | weeks
  final double rateWeek, rateMonth, rateYear, rateAll;
  final List<int> weekdayCounts; // Mon..Sun, number of completed days
  final List<int> weeklyBars; // completed days per week, oldest -> current (8)
}

class HabitStore extends ChangeNotifier {
  HabitStore(this.data, this.settings) {
    data.onReload.add(load);
  }

  final DataStore data;
  final SettingsService settings;

  List<Habit> habits = [];
  final Map<String, Map<String, int>> _logs = {};

  Database get _db => data.db;
  int get weekStart => settings.weekStart;

  Future<void> load() async {
    habits = (await _db.query('habits', where: 'del=0')).map(Habit.fromMap).toList()
      ..sort((a, b) => a.created.compareTo(b.created));
    _logs.clear();
    for (final r in await _db.query('habit_logs', where: 'del=0')) {
      (_logs[r['habit_id'] as String] ??= {})[r['day'] as String] = r['value'] as int;
    }
    notifyListeners();
  }

  List<Habit> get active => habits.where((h) => !h.archived).toList();

  Future<void> save(Habit h) async {
    await data.put('habits', h.toMap());
    final i = habits.indexWhere((e) => e.id == h.id);
    if (i >= 0) {
      habits[i] = h;
    } else {
      habits.add(h);
    }
    notifyListeners();
  }

  Future<void> delete(Habit h) async {
    await data.tombstone('habits', 'id=?', [h.id]);
    await data.tombstone('habit_logs', 'habit_id=?', [h.id]);
    habits.removeWhere((e) => e.id == h.id);
    _logs.remove(h.id);
    notifyListeners();
  }

  // ---- logging ----
  int valueOn(Habit h, DateTime d) => _logs[h.id]?[dayKey(d)] ?? 0;

  bool doneOn(Habit h, DateTime d) => valueOn(h, d) >= (h.isCount ? h.target : 1);

  Future<void> setValue(Habit h, DateTime d, int v) async {
    final k = dayKey(d);
    v = v < 0 ? 0 : v;
    if (v == 0) {
      _logs[h.id]?.remove(k);
      await data.tombstone('habit_logs', 'habit_id=? AND day=?', [h.id, k]);
    } else {
      (_logs[h.id] ??= {})[k] = v;
      await data.put('habit_logs', {'habit_id': h.id, 'day': k, 'value': v});
    }
    notifyListeners();
  }

  /// Tap on a check: done <-> not done (count habits jump to / from the target).
  Future<void> toggle(Habit h, DateTime d) =>
      setValue(h, d, doneOn(h, d) ? 0 : (h.isCount ? h.target : 1));

  Future<void> markNotified(Habit h) async {
    h.lastNotified = dayKey(DateTime.now());
    await _db.update('habits', {'lastNotified': h.lastNotified}, where: 'id=?', whereArgs: [h.id]);
  }

  // ---- schedule ----
  bool scheduledOn(Habit h, DateTime d) => switch (h.freq) {
        'weekdays' => (h.weekdays >> (d.weekday - 1)) & 1 == 1,
        _ => true, // daily, and "times per week" (any day can count)
      };

  DateTime startDay(Habit h) {
    var s = dayOnly(h.created);
    for (final k in _logs[h.id]?.keys ?? const <String>[]) {
      final d = parseDayKey(k);
      if (d.isBefore(s)) s = d;
    }
    return s;
  }

  int _doneInWeek(Habit h, DateTime weekFirst) {
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (doneOn(h, addDays(weekFirst, i))) n++;
    }
    return n;
  }

  /// Habits that should appear in today's list.
  List<Habit> dueToday([DateTime? now]) {
    final t = dayOnly(now ?? DateTime.now());
    return active.where((h) => scheduledOn(h, t)).toList();
  }

  int doneTodayCount() {
    final t = dayOnly(DateTime.now());
    return dueToday().where((h) => doneOn(h, t)).length;
  }

  /// Number of days done in the current week for "times per week" habits.
  int doneThisWeek(Habit h) =>
      _doneInWeek(h, startOfWeek(DateTime.now(), weekStart));

  // ---- stats ----
  double _rate(Habit h, DateTime from, DateTime to) {
    final today = dayOnly(DateTime.now());
    var start = startDay(h);
    if (from.isAfter(start)) start = from;
    var end = to.isAfter(today) ? today : to;
    if (end == today && !doneOn(h, today)) end = addDays(today, -1);
    if (end.isBefore(start)) return 0;
    final days = end.difference(start).inDays + 1;
    if (h.freq == 'times') {
      var done = 0;
      for (var i = 0; i < days; i++) {
        if (doneOn(h, addDays(start, i))) done++;
      }
      final expected = days * h.timesPerWeek / 7;
      return expected <= 0 ? 0 : (done / expected).clamp(0.0, 1.0);
    }
    var sched = 0, done = 0;
    for (var i = 0; i < days; i++) {
      final d = addDays(start, i);
      if (!scheduledOn(h, d)) continue;
      sched++;
      if (doneOn(h, d)) done++;
    }
    return sched == 0 ? 0 : done / sched;
  }

  HabitStats statsFor(Habit h) {
    final today = dayOnly(DateTime.now());
    final start = startDay(h);
    var current = 0, best = 0;
    String unit = 'days';

    if (h.freq == 'times') {
      unit = 'weeks';
      final thisWeek = startOfWeek(today, weekStart);
      var w = thisWeek;
      if (_doneInWeek(h, w) < h.timesPerWeek) w = addDays(w, -7); // still in progress
      while (!w.isBefore(startOfWeek(start, weekStart)) && _doneInWeek(h, w) >= h.timesPerWeek) {
        current++;
        w = addDays(w, -7);
      }
      var run = 0;
      for (var w2 = startOfWeek(start, weekStart);
          !w2.isAfter(thisWeek);
          w2 = addDays(w2, 7)) {
        if (_doneInWeek(h, w2) >= h.timesPerWeek) {
          run++;
          if (run > best) best = run;
        } else if (w2 != thisWeek) {
          run = 0;
        }
      }
    } else {
      var d = today;
      if (scheduledOn(h, d) && !doneOn(h, d)) d = addDays(d, -1); // today still pending
      while (!d.isBefore(start)) {
        if (!scheduledOn(h, d)) {
          d = addDays(d, -1);
          continue;
        }
        if (!doneOn(h, d)) break;
        current++;
        d = addDays(d, -1);
      }
      var run = 0;
      final days = today.difference(start).inDays;
      for (var i = 0; i <= days; i++) {
        final x = addDays(start, i);
        if (!scheduledOn(h, x)) continue;
        if (doneOn(h, x)) {
          run++;
          if (run > best) best = run;
        } else if (x != today) {
          run = 0;
        }
      }
    }

    var total = 0;
    final weekdayCounts = List.filled(7, 0);
    for (final e in (_logs[h.id] ?? const <String, int>{}).entries) {
      if (e.value >= (h.isCount ? h.target : 1)) {
        total++;
        weekdayCounts[parseDayKey(e.key).weekday - 1]++;
      }
    }

    final thisWeek = startOfWeek(today, weekStart);
    final bars = [
      for (var i = 7; i >= 0; i--) _doneInWeek(h, addDays(thisWeek, -7 * i)),
    ];

    return HabitStats(
      current: current,
      best: best,
      totalDone: total,
      unit: unit,
      rateWeek: _rate(h, addDays(today, -6), today),
      rateMonth: _rate(h, addDays(today, -29), today),
      rateYear: _rate(h, addDays(today, -364), today),
      rateAll: _rate(h, start, today),
      weekdayCounts: weekdayCounts,
      weeklyBars: bars,
    );
  }

  /// Overall completion across all active habits for the last [days] days.
  double overallRate(int days) {
    final list = active;
    if (list.isEmpty) return 0;
    final today = dayOnly(DateTime.now());
    var sum = 0.0, n = 0;
    for (final h in list) {
      final r = _rate(h, addDays(today, -(days - 1)), today);
      sum += r;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Fraction of today's habits finished on [d] (for the 7-day strip).
  double dayProgress(DateTime d) {
    final list = active.where((h) => scheduledOn(h, d) && !startDay(h).isAfter(d)).toList();
    if (list.isEmpty) return 0;
    return list.where((h) => doneOn(h, d)).length / list.length;
  }

  /// Habits whose reminder time has passed today and are still not done.
  List<Habit> dueReminders(DateTime now) {
    final today = dayOnly(now);
    final key = dayKey(now);
    return active.where((h) {
      if (h.remindTime == null || h.lastNotified == key) return false;
      if (!scheduledOn(h, today) || doneOn(h, today)) return false;
      if (h.freq == 'times' && doneThisWeek(h) >= h.timesPerWeek) return false;
      final p = h.remindTime!.split(':');
      final at = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      return !now.isBefore(at);
    }).toList();
  }
}
