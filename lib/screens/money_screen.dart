import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/helpers.dart';
import '../data/habit_models.dart';
import '../data/money_store.dart';
import '../widgets/common.dart';
import '../widgets/fx.dart';
import 'categories_screen.dart';
import 'expense_editor.dart';
import 'recurring_screen.dart';

class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  Period _period = Period.month;
  int _offset = 0;
  Range? _custom;
  String _query = '';
  String? _catFilter;

  static const _labels = {
    Period.today: 'Today',
    Period.week: 'This week',
    Period.month: 'This month',
    Period.year: 'This year',
    Period.all: 'All time',
    Period.custom: 'Custom',
  };

  bool get _navigable => _period != Period.all && _period != Period.custom;

  String _rangeLabel(Range r) {
    final f = DateFormat('d MMM');
    switch (_period) {
      case Period.today:
        return _offset == 0 ? 'Today' : (_offset == -1 ? 'Yesterday' : DateFormat('EEE, d MMM y').format(r.start));
      case Period.week:
        return '${f.format(r.start)} – ${f.format(addDays(r.end, -1))}';
      case Period.month:
        return DateFormat('MMMM y').format(r.start);
      case Period.year:
        return '${r.start.year}';
      case Period.all:
        return 'Since ${DateFormat('d MMM y').format(r.start)}';
      case Period.custom:
        return '${DateFormat('d MMM y').format(r.start)} – ${DateFormat('d MMM y').format(addDays(r.end, -1))}';
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _custom == null
          ? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now)
          : DateTimeRange(start: _custom!.start, end: addDays(_custom!.end, -1)),
    );
    if (res != null) {
      setState(() {
        _custom = Range(dayOnly(res.start), addDays(dayOnly(res.end), 1));
        _period = Period.custom;
        _offset = 0;
      });
    }
  }

  Future<void> _exportCsv(MoneyStore m, List<Expense> list) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export to CSV',
      fileName: 'expenses-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return;
    await File(path).writeAsString(m.toCsv(list));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported ${list.length} entries')));
    }
  }

  /// Buckets for the trend chart: label + amount.
  List<(String, double)> _buckets(MoneyStore m, Range r, Summary s) {
    final today = dayOnly(DateTime.now());
    final end = r.end.isAfter(addDays(today, 1)) ? addDays(today, 1) : r.end;
    final byMonth = _period == Period.year ||
        _period == Period.all ||
        (_period == Period.custom && r.days > 62);
    if (byMonth) {
      final out = <(String, double)>[];
      var d = DateTime(r.start.year, r.start.month, 1);
      final last = _period == Period.year ? DateTime(r.start.year, 12, 1) : DateTime(end.year, end.month, 1);
      while (!d.isAfter(last)) {
        final next = DateTime(d.year, d.month + 1, 1);
        var sum = 0.0;
        s.spentByDay.forEach((day, v) {
          if (!day.isBefore(d) && day.isBefore(next)) sum += v;
        });
        out.add((DateFormat(_period == Period.all || r.days > 400 ? 'MMM yy' : 'MMM').format(d), sum));
        d = next;
      }
      return out;
    }
    final fmt = _period == Period.week ? DateFormat('E') : DateFormat('d');
    return [
      for (var d = r.start; d.isBefore(r.end); d = addDays(d, 1)) (fmt.format(d), s.spentByDay[d] ?? 0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final cs = Theme.of(context).colorScheme;
    final r = m.rangeFor(_period, _offset, _custom);
    final s = m.summarize(r);
    final today = dayOnly(DateTime.now());

    // previous period of the same length, for the comparison line
    Range? prev;
    if (_period != Period.all) {
      if (_period == Period.custom) {
        prev = Range(addDays(r.start, -r.days), r.start);
      } else {
        prev = m.rangeFor(_period, _offset - 1, _custom);
      }
    }
    final prevSpent = prev == null ? null : m.summarize(prev).spent;

    final endCap = r.end.isAfter(addDays(today, 1)) ? addDays(today, 1) : r.end;
    final elapsed = endCap.difference(r.start).inDays.clamp(1, 100000);

    // entries shown in the list
    final list = m.expenses.where((e) {
      if (!r.contains(e.date)) return false;
      if (_catFilter != null && e.category != _catFilter) return false;
      if (_query.isNotEmpty) {
        final name = m.labelOf(e);
        if (!'${e.note} $name ${e.method} ${e.amount}'.toLowerCase().contains(_query)) return false;
      }
      return true;
    }).toList();

    final byDay = <DateTime, List<Expense>>{};
    for (final e in list) {
      (byDay[dayOnly(e.date)] ??= []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // pie data
    final cats = s.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final buckets = _period == Period.today ? <(String, double)>[] : _buckets(m, r, s);
    final maxBucket = buckets.fold<double>(0, (a, b) => b.$2 > a ? b.$2 : a);
    final step = (buckets.length / 8).ceil().clamp(1, 100);

    final overall = m.budgets[''];
    final monthSpent = _period == Period.month ? s.spent : null;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExpenseEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: revealAll([
            // period chips + menu
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final p in Period.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                        child: ChoiceChip(
                          label: Text(_labels[p]!),
                          selected: _period == p,
                          onSelected: (_) {
                            if (p == Period.custom) {
                              _pickCustom();
                            } else {
                              setState(() {
                                _period = p;
                                _offset = 0;
                              });
                            }
                          },
                        ),
                      ),
                  ]),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'cats':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen()));
                    case 'rec':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringScreen()));
                    case 'csv':
                      _exportCsv(m, list);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cats', child: Text('Categories & budgets')),
                  PopupMenuItem(value: 'rec', child: Text('Recurring entries')),
                  PopupMenuItem(value: 'csv', child: Text('Export shown entries (CSV)')),
                ],
              ),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _navigable ? () => setState(() => _offset--) : null),
              TextButton(
                onPressed: _period == Period.custom ? _pickCustom : null,
                child: Text(_rangeLabel(r), style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _navigable && _offset < 0 ? () => setState(() => _offset++) : null),
            ]),
            const SizedBox(height: 4),
            StatGrid(minWidth: 170, children: [
              StatCard(
                  label: 'Spent',
                  value: m.fmt(s.spent),
                  number: s.spent,
                  format: m.fmt,
                  icon: Icons.arrow_upward,
                  color: Colors.redAccent,
                  sub: '${s.count} entries'),
              StatCard(
                  label: 'Income',
                  value: m.fmt(s.income),
                  number: s.income,
                  format: m.fmt,
                  icon: Icons.arrow_downward,
                  color: Colors.green),
              StatCard(
                  label: 'Balance',
                  value: m.fmt(s.balance),
                  number: s.balance,
                  format: m.fmt,
                  icon: Icons.account_balance_wallet_outlined,
                  color: s.balance >= 0 ? cs.primary : Colors.redAccent),
              StatCard(
                  label: 'Daily average',
                  value: m.fmt(s.spent / elapsed),
                  number: s.spent / elapsed,
                  format: m.fmt,
                  icon: Icons.calendar_today,
                  sub: 'over $elapsed day${elapsed == 1 ? '' : 's'}'),
            ]),

            if (prevSpent != null && (prevSpent > 0 || s.spent > 0))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Builder(builder: (_) {
                  if (prevSpent == 0) {
                    return Text('Nothing spent in the previous period to compare with.',
                        style: Theme.of(context).textTheme.bodySmall);
                  }
                  final diff = (s.spent - prevSpent) / prevSpent;
                  final up = diff > 0;
                  return Row(children: [
                    Icon(up ? Icons.trending_up : Icons.trending_down,
                        size: 18, color: up ? Colors.redAccent : Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          '${(diff.abs() * 100).round()}% ${up ? 'more' : 'less'} than the previous period (${m.fmt(prevSpent)})'),
                    ),
                  ]);
                }),
              ),

            if (overall != null && monthSpent != null) ...[
              sectionTitle(context, 'Monthly budget'),
              _BudgetBar(label: 'All spending', spent: monthSpent, budget: overall, m: m),
            ],
            if (_period == Period.month)
              for (final e in m.budgets.entries.where((e) => e.key.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _BudgetBar(
                      label: m.cat(e.key)?.name ?? e.key,
                      spent: s.byCategory[e.key] ?? 0,
                      budget: e.value,
                      m: m),
                ),

            if (cats.isNotEmpty) ...[
              sectionTitle(context, 'Where it went'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(builder: (context, c) {
                    final pie = SizedBox(
                      width: 190,
                      height: 190,
                      child: PieChart(duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic, PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 42,
                        sections: [
                          for (final e in cats)
                            PieChartSectionData(
                              value: e.value,
                              color: palette[(m.cat(e.key)?.color ?? 9) % palette.length],
                              radius: 46,
                              title: e.value / s.spent >= 0.08 ? pct(e.value / s.spent) : '',
                              titleStyle: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                        ],
                      )),
                    );
                    final legend = Column(children: [
                      for (final e in cats)
                        InkWell(
                          onTap: () => setState(() => _catFilter = _catFilter == e.key ? null : e.key),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                      color: palette[(m.cat(e.key)?.color ?? 9) % palette.length],
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(m.cat(e.key)?.name ?? e.key,
                                      style: TextStyle(
                                          fontWeight: _catFilter == e.key ? FontWeight.bold : null))),
                              Text(m.fmt(e.value)),
                              SizedBox(
                                  width: 44,
                                  child: Text(pct(e.value / s.spent),
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context).textTheme.bodySmall)),
                            ]),
                          ),
                        ),
                    ]);
                    return c.maxWidth > 560
                        ? Row(children: [pie, const SizedBox(width: 24), Expanded(child: legend)])
                        : Column(children: [pie, const SizedBox(height: 12), legend]);
                  }),
                ),
              ),
            ],

            if (buckets.length > 1 && maxBucket > 0) ...[
              sectionTitle(context, 'Spending over time'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
                  child: SizedBox(
                    height: 200,
                    child: BarChart(duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic, BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxBucket * 1.15,
                      gridData: const FlGridData(drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                              '${buckets[g.x].$1}\n${m.fmt(rod.toY)}',
                              TextStyle(color: cs.onInverseSurface, fontSize: 12)),
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        leftTitles: const AxisTitles(),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            getTitlesWidget: (v, _) => v.toInt() % step == 0 && v.toInt() < buckets.length
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(buckets[v.toInt()].$1, style: const TextStyle(fontSize: 10)))
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < buckets.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: buckets[i].$2,
                              color: cs.primary,
                              width: buckets.length > 20 ? 6 : 14,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ]),
                      ],
                    )),
                  ),
                ),
              ),
            ],

            if (s.biggest != null) ...[
              sectionTitle(context, 'Biggest expense'),
              Card(
                child: ListTile(
                  leading: Icon(moneyIcons[(m.cat(s.biggest!.category)?.icon ?? 6) % moneyIcons.length]),
                  title: Text(m.fmt(s.biggest!.amount)),
                  subtitle: Text(
                      '${m.labelOf(s.biggest!)} · ${DateFormat('d MMM').format(s.biggest!.date)}${s.biggest!.note.isEmpty ? '' : ' · ${s.biggest!.note}'}'),
                  onTap: () => showExpenseEditor(context, s.biggest),
                ),
              ),
            ],

            sectionTitle(context, 'Entries'),
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'Search entries', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String?>(
                value: _catFilter,
                hint: const Text('All categories'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All categories')),
                  for (final c in m.cats) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _catFilter = v),
              ),
            ]),
            const SizedBox(height: 8),
            if (days.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No entries in this period.'))),
            for (final d in days) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Row(children: [
                  Text(DateFormat('EEE, d MMM').format(d), style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  Text(
                      m.fmt(byDay[d]!.fold<double>(0, (a, e) => a + (e.isIncome ? 0 : e.amount))),
                      style: Theme.of(context).textTheme.labelLarge),
                ]),
              ),
              for (final e in byDay[d]!)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          palette[(m.cat(e.category)?.color ?? 9) % palette.length].withValues(alpha: 0.18),
                      child: Icon(moneyIcons[(m.cat(e.category)?.icon ?? 6) % moneyIcons.length],
                          color: palette[(m.cat(e.category)?.color ?? 9) % palette.length]),
                    ),
                    title: Text(m.labelOf(e)),
                    subtitle: Text(
                        '${e.method}${e.note.isEmpty ? '' : ' · ${e.note}'}${e.recurringId != null ? ' · recurring' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (e.fileId != null) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.attach_file, size: 16)),
                      Text('${e.isIncome ? '+' : '-'}${m.fmt(e.amount)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: e.isIncome ? Colors.green : null)),
                    ]),
                    onTap: () => showExpenseEditor(context, e),
                  ),
                ),
            ],
          ])),
        ),
      ),
    );
  }
}

class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.label, required this.spent, required this.budget, required this.m});
  final String label;
  final double spent, budget;
  final MoneyStore m;

  @override
  Widget build(BuildContext context) {
    final ratio = budget <= 0 ? 0.0 : spent / budget;
    final color = ratio >= 1 ? Colors.redAccent : (ratio >= 0.8 ? Colors.orange : Colors.green);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
            Text('${m.fmt(spent)} / ${m.fmt(budget)}'),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              color: color,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 6),
          Text(
              ratio >= 1
                  ? 'Over budget by ${m.fmt(spent - budget)}'
                  : '${m.fmt(budget - spent)} left (${pct(ratio)} used)',
              style: TextStyle(color: color, fontSize: 12)),
        ]),
      ),
    );
  }
}
