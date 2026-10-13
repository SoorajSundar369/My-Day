import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/helpers.dart';
import '../data/habit_models.dart';
import '../data/habit_store.dart';
import '../widgets/common.dart';
import '../widgets/fx.dart';
import 'habit_editor.dart';

class HabitDetailScreen extends StatelessWidget {
  const HabitDetailScreen({super.key, required this.habitId});
  final String habitId;

  Future<void> _setCount(BuildContext context, Habit h, DateTime d) async {
    final store = context.read<HabitStore>();
    final c = TextEditingController(text: '${store.valueOn(h, d)}');
    final v = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(DateFormat('EEE, d MMM').format(d)),
        content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Amount ${h.unit}'.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, int.tryParse(c.text) ?? 0),
              child: const Text('Save')),
        ],
      ),
    );
    if (v != null) await store.setValue(h, d, v);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitStore>();
    final h = store.habits.where((e) => e.id == habitId).firstOrNull;
    if (h == null) return const Scaffold(body: Center(child: Text('Habit deleted')));
    final color = palette[h.color % palette.length];
    final s = store.statsFor(h);
    final cs = Theme.of(context).colorScheme;
    final today = dayOnly(DateTime.now());

    final milestones = s.unit == 'weeks' ? [4, 12, 26, 52] : [7, 30, 100, 365];
    final bestDay = s.weekdayCounts.reduce((a, b) => a > b ? a : b);
    final bestIdx = s.weekdayCounts.indexOf(bestDay);
    final weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final thisWeek = startOfWeek(today, store.weekStart);

    return Scaffold(
      appBar: AppBar(
        title: Text(h.name),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => showHabitEditor(context, h)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                h.archived = !h.archived;
                await store.save(h);
              } else if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete habit?'),
                    content: const Text('All its history will be removed. Archive it instead to keep the history.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await store.delete(h);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archive', child: Text(h.archived ? 'Restore habit' : 'Archive (pause) habit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete habit')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(16), children: revealAll([
            if (h.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('“${h.note}”', style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            StatGrid(children: [
              StatCard(
                  label: 'Current streak',
                  value: '${s.current} ${s.unit}',
                  number: s.current.toDouble(),
                  format: (v) => '${v.round()} ${s.unit}',
                  icon: Icons.local_fire_department,
                  color: Colors.deepOrange),
              StatCard(
                  label: 'Best streak',
                  value: '${s.best} ${s.unit}',
                  number: s.best.toDouble(),
                  format: (v) => '${v.round()} ${s.unit}',
                  icon: Icons.emoji_events,
                  color: color),
              StatCard(
                  label: 'Total check-ins',
                  value: '${s.totalDone}',
                  number: s.totalDone.toDouble(),
                  format: (v) => '${v.round()}',
                  icon: Icons.task_alt,
                  color: color),
              StatCard(
                  label: 'Started',
                  value: DateFormat('d MMM y').format(store.startDay(h)),
                  sub: '${today.difference(store.startDay(h)).inDays + 1} days ago',
                  icon: Icons.flag,
                  color: color),
            ]),
            sectionTitle(context, 'Completion rate'),
            StatGrid(minWidth: 120, children: [
              _RateCard('7 days', s.rateWeek, color),
              _RateCard('30 days', s.rateMonth, color),
              _RateCard('1 year', s.rateYear, color),
              _RateCard('All time', s.rateAll, color),
            ]),
            sectionTitle(context, 'History',
                trailing: Text('Tap a day to edit', style: Theme.of(context).textTheme.bodySmall)),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _Heatmap(
                  habit: h,
                  store: store,
                  color: color,
                  onTapDay: (d) {
                    if (h.isCount) {
                      _setCount(context, h, d);
                    } else {
                      store.toggle(h, d);
                    }
                  },
                ),
              ),
            ),
            sectionTitle(context, 'Last 8 weeks'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                child: SizedBox(
                  height: 180,
                  child: BarChart(duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic, BarChartData(
                    maxY: 7,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: 1,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(DateFormat('d MMM').format(addDays(thisWeek, -7 * (7 - v.toInt()))),
                                style: const TextStyle(fontSize: 10)),
                          ),
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < s.weeklyBars.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                              toY: s.weeklyBars[i].toDouble(),
                              color: color,
                              width: 16,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                        ]),
                    ],
                  )),
                ),
              ),
            ),
            sectionTitle(context, 'Best day of the week'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bestDay == 0 ? 'Not enough data yet.' : '${weekdayNames[bestIdx]} — $bestDay check-ins',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Column(children: [
                          Container(
                            height: bestDay == 0 ? 4 : 4 + 50 * s.weekdayCounts[i] / bestDay,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                                color: i == bestIdx && bestDay > 0 ? color : color.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(4)),
                          ),
                          const SizedBox(height: 4),
                          Text(weekdayNames[i].substring(0, 3), style: const TextStyle(fontSize: 11)),
                        ]),
                      ),
                  ]),
                ]),
              ),
            ),
            sectionTitle(context, 'Milestones'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in milestones)
                Chip(
                  avatar: Icon(Icons.emoji_events,
                      size: 18, color: s.best >= m ? Colors.amber.shade700 : cs.outline),
                  label: Text('$m ${s.unit}'),
                  side: BorderSide(color: s.best >= m ? Colors.amber.shade700 : cs.outlineVariant),
                ),
            ]),
            const SizedBox(height: 40),
          ])),
        ),
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(pct(value),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
                value: value, color: color, minHeight: 5, borderRadius: BorderRadius.circular(5)),
          ]),
        ),
      );
}

/// GitHub-style grid: one column per week, one row per weekday.
class _Heatmap extends StatelessWidget {
  const _Heatmap({
    required this.habit,
    required this.store,
    required this.color,
    required this.onTapDay,
  });

  final Habit habit;
  final HabitStore store;
  final Color color;
  final ValueChanged<DateTime> onTapDay;

  static const weeks = 26;
  static const cell = 18.0;
  static const gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dayOnly(DateTime.now());
    final first = addDays(startOfWeek(today, store.weekStart), -7 * (weeks - 1));
    final start = store.startDay(habit);

    Color fill(DateTime d) {
      final v = store.valueOn(habit, d);
      final target = habit.isCount ? habit.target : 1;
      if (v >= target) return color;
      if (v > 0) return color.withValues(alpha: 0.25 + 0.5 * v / target);
      if (d.isBefore(start) || !store.scheduledOn(habit, d)) return cs.surfaceContainerLow;
      return cs.surfaceContainerHighest;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true, // newest weeks visible first
      child: Row(children: [
        for (var w = 0; w < weeks; w++)
          _Pop(
            delayMs: w * 22,
            child: Column(children: [
            for (var r = 0; r < 7; r++)
              Builder(builder: (_) {
                final d = addDays(first, w * 7 + r);
                final future = d.isAfter(today);
                return Padding(
                  padding: const EdgeInsets.all(gap / 2),
                  child: future
                      ? const SizedBox(width: cell, height: cell)
                      : Tooltip(
                          message:
                              '${DateFormat('EEE, d MMM').format(d)}${habit.isCount ? '  ·  ${store.valueOn(habit, d)}/${habit.target}' : ''}',
                          child: InkWell(
                            onTap: () => onTapDay(d),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              width: cell,
                              height: cell,
                              decoration: BoxDecoration(
                                color: fill(d),
                                borderRadius: BorderRadius.circular(4),
                                border: d == today ? Border.all(color: cs.onSurface, width: 1.5) : null,
                              ),
                            ),
                          ),
                        ),
                );
              }),
          ])),
      ]),
    );
  }
}

/// Springs its child in after [delayMs] (used for the heatmap columns).
class _Pop extends StatelessWidget {
  const _Pop({required this.child, required this.delayMs});
  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    if (!m.on) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + delayMs),
      curve: Interval(delayMs / (350 + delayMs), 1, curve: Curves.easeOutBack),
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: c),
      ),
      child: child,
    );
  }
}
