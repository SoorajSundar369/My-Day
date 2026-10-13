import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../core/helpers.dart';
import '../services/settings_service.dart';
import 'data_store.dart';
import 'habit_models.dart';

enum Period { today, week, month, year, all, custom }

/// Half-open date range [start, end).
class Range {
  const Range(this.start, this.end);
  final DateTime start;
  final DateTime end;
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  int get days => end.difference(start).inDays;
}

class Summary {
  double spent = 0, income = 0;
  final Map<String, double> byCategory = {};
  final Map<DateTime, double> spentByDay = {};
  Expense? biggest;
  int count = 0;
  double get balance => income - spent;
}

class MoneyStore extends ChangeNotifier {
  MoneyStore(this.data, this.settings) {
    data.onReload.add(load);
  }

  final DataStore data;
  final SettingsService settings;
  final _uuid = const Uuid();

  List<ExpenseCategory> cats = [];
  List<Expense> expenses = [];
  Map<String, double> budgets = {}; // '' = overall monthly budget
  List<Recurring> recurring = [];

  Database get _db => data.db;
  String get symbol => settings.currency;
  String fmt(num v) => money(v, symbol);
  String newId() => _uuid.v4();

  Future<void> load() async {
    cats = (await _db.query('expense_cats', where: 'del=0')).map(ExpenseCategory.fromMap).toList();
    expenses = (await _db.query('expenses', where: 'del=0')).map(Expense.fromMap).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    budgets = {
      for (final r in await _db.query('budgets', where: 'del=0')) r['category'] as String: (r['amount'] as num).toDouble()
    };
    recurring = (await _db.query('recurring', where: 'del=0')).map(Recurring.fromMap).toList();
    notifyListeners();
    await processRecurring();
  }

  ExpenseCategory? cat(String id) {
    for (final c in cats) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// What to show for an entry: its one-off custom label, else its category name.
  String labelOf(Expense e) => e.customName.isNotEmpty ? e.customName : (cat(e.category)?.name ?? e.category);

  List<ExpenseCategory> catsOf(String kind) => cats.where((c) => c.kind == kind).toList();

  // ---- expenses ----
  Future<void> save(Expense e) async {
    await data.put('expenses', e.toMap());
    final i = expenses.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      expenses[i] = e;
    } else {
      expenses.add(e);
    }
    expenses.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  Future<void> delete(Expense e) async {
    await data.tombstone('expenses', 'id=?', [e.id]);
    expenses.removeWhere((x) => x.id == e.id);
    notifyListeners();
  }

  // ---- categories ----
  Future<void> saveCat(ExpenseCategory c) async {
    await data.put('expense_cats', c.toMap());
    final i = cats.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      cats[i] = c;
    } else {
      cats.add(c);
    }
    notifyListeners();
  }

  /// Entries of a deleted category move to "other".
  Future<void> deleteCat(ExpenseCategory c) async {
    final fallback = c.kind == 'income' ? 'other_income' : 'other';
    await data.touch('expenses', {'category': fallback}, 'category=?', [c.id]);
    await data.tombstone('expense_cats', 'id=?', [c.id]);
    await data.tombstone('budgets', 'category=?', [c.id]);
    budgets.remove(c.id);
    cats.removeWhere((x) => x.id == c.id);
    for (final e in expenses) {
      if (e.category == c.id) e.category = fallback;
    }
    notifyListeners();
  }

  Future<void> setBudget(String category, double? amount) async {
    if (amount == null || amount <= 0) {
      await data.tombstone('budgets', 'category=?', [category]);
      budgets.remove(category);
    } else {
      await data.put('budgets', {'category': category, 'amount': amount});
      budgets[category] = amount;
    }
    notifyListeners();
  }

  // ---- recurring ----
  Future<void> saveRecurring(Recurring r) async {
    await data.put('recurring', r.toMap());
    final i = recurring.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      recurring[i] = r;
    } else {
      recurring.add(r);
    }
    notifyListeners();
    await processRecurring();
  }

  Future<void> deleteRecurring(Recurring r) async {
    await data.tombstone('recurring', 'id=?', [r.id]);
    recurring.removeWhere((x) => x.id == r.id);
    notifyListeners();
  }

  /// Adds an entry for every recurring item whose date has arrived.
  Future<void> processRecurring() async {
    final now = DateTime.now();
    for (final r in recurring.where((r) => r.active)) {
      var changed = false;
      var guard = 0;
      while (!r.next.isAfter(now) && guard++ < 500) {
        await save(Expense(
          id: 'rec-${r.id}-${r.next.millisecondsSinceEpoch}',
          amount: r.amount,
          kind: r.kind,
          category: r.category,
          method: r.method,
          note: r.note,
          date: r.next,
          recurringId: r.id,
        ));
        r.next = r.advance(r.next);
        changed = true;
      }
      if (changed) {
        await data.put('recurring', r.toMap());
        notifyListeners();
      }
    }
  }

  // ---- periods & summaries ----
  Range rangeFor(Period p, int offset, Range? custom) {
    final now = DateTime.now();
    final today = dayOnly(now);
    switch (p) {
      case Period.today:
        final d = addDays(today, offset);
        return Range(d, addDays(d, 1));
      case Period.week:
        final s = addDays(startOfWeek(today, settings.weekStart), offset * 7);
        return Range(s, addDays(s, 7));
      case Period.month:
        final s = DateTime(today.year, today.month + offset, 1);
        return Range(s, DateTime(s.year, s.month + 1, 1));
      case Period.year:
        final s = DateTime(today.year + offset, 1, 1);
        return Range(s, DateTime(s.year + 1, 1, 1));
      case Period.all:
        var s = today;
        for (final e in expenses) {
          if (e.date.isBefore(s)) s = dayOnly(e.date);
        }
        return Range(s, addDays(today, 1));
      case Period.custom:
        return custom ?? Range(DateTime(today.year, today.month, 1), addDays(today, 1));
    }
  }

  Summary summarize(Range r, {bool Function(Expense)? where}) {
    final s = Summary();
    for (final e in expenses) {
      if (!r.contains(e.date)) continue;
      if (where != null && !where(e)) continue;
      s.count++;
      if (e.isIncome) {
        s.income += e.amount;
      } else {
        s.spent += e.amount;
        s.byCategory[e.category] = (s.byCategory[e.category] ?? 0) + e.amount;
        final d = dayOnly(e.date);
        s.spentByDay[d] = (s.spentByDay[d] ?? 0) + e.amount;
        if (s.biggest == null || e.amount > s.biggest!.amount) s.biggest = e;
      }
    }
    return s;
  }

  /// Spent in the calendar month containing [d], optionally for one category.
  double spentInMonth(DateTime d, {String? category}) {
    final r = Range(DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 1));
    final s = summarize(r);
    return category == null ? s.spent : (s.byCategory[category] ?? 0);
  }

  String toCsv(List<Expense> list) {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('Date,Type,Category,Amount,Method,Note\n');
    for (final e in list) {
      b.writeln([
        dayKey(e.date),
        e.kind,
        q(labelOf(e)),
        e.amount,
        e.method,
        q(e.note),
      ].join(','));
    }
    return b.toString();
  }
}
