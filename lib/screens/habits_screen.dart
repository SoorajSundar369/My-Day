import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/helpers.dart';
import '../data/habit_models.dart';
import '../data/habit_store.dart';
import '../widgets/common.dart';
import '../widgets/fx.dart';
import 'habit_detail.dart';
import 'habit_editor.dart';

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitStore>();
    final today = dayOnly(DateTime.now());
    final due = store.dueToday();
    final other = store.active.where((h) => !due.contains(h)).toList();
    final done = store.doneTodayCount();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showHabitEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New habit'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        if (store.active.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(
                child: Text('No habits yet.\nStart small: one habit you want to keep.',
                    textAlign: TextAlign.center)),
          )
        else ...[
          Reveal(
            child: Tilt(
              strength: 0.5,
              child: Glass(
                blur: true,
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Row(children: [
                    AnimatedRing(
                      value: due.isEmpty ? 0 : done / due.length,
                      size: 112,
                      stroke: 13,
                      colors: const [Color(0xFFFF9A3C), Color(0xFFFF4E6A)],
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedCount(
                            value: done.toDouble(),
                            format: (v) => '${v.round()}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text('of ${due.length}', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            due.isEmpty
                                ? 'Nothing scheduled today'
                                : (done == due.length ? 'All done. Great job!' : '${due.length - done} to go today'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _Mini('7 days', pct(store.overallRate(7)))),
                          Expanded(child: _Mini('30 days', pct(store.overallRate(30)))),
                          Expanded(child: _Mini('1 year', pct(store.overallRate(365)))),
                        ]),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    for (var i = 6; i >= 0; i--)
                      _DayRing(day: addDays(today, -i), value: store.dayProgress(addDays(today, -i))),
                  ]),
                ]),
              ),
            ),
          ),
          sectionTitle(context, 'Today'),
          if (due.isEmpty) Text('Enjoy your rest day.', style: TextStyle(color: cs.outline)),
          for (final h in due)
            Reveal(
                index: due.indexOf(h) + 1,
                child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Tilt(strength: 0.4, child: HabitTile(h)))),
          if (other.isNotEmpty) ...[
            sectionTitle(context, 'Not scheduled today'),
            for (final h in other)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Opacity(opacity: 0.6, child: HabitTile(h))),
          ],
        ],
        if (store.habits.any((h) => h.archived)) ...[
          sectionTitle(context, 'Archived'),
          for (final h in store.habits.where((h) => h.archived))
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Opacity(opacity: 0.5, child: HabitTile(h))),
        ],
      ]),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _DayRing extends StatelessWidget {
  const _DayRing({required this.day, required this.value});
  final DateTime day;
  final double value;

  @override
  Widget build(BuildContext context) {
    final isToday = dayOnly(DateTime.now()) == day;
    return Column(children: [
      Text(DateFormat('E').format(day).substring(0, 1),
          style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 4),
      SizedBox(
        width: 34,
        height: 34,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
              value: value,
              strokeWidth: 4,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest),
          Text('${day.day}',
              style: TextStyle(fontSize: 11, fontWeight: isToday ? FontWeight.bold : null)),
        ]),
      ),
    ]);
  }
}

class HabitTile extends StatelessWidget {
  const HabitTile(this.habit, {super.key});
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitStore>();
    final h = habit;
    final today = dayOnly(DateTime.now());
    final color = palette[h.color % palette.length];
    final done = store.doneOn(h, today);
    final stats = store.statsFor(h);
    final value = store.valueOn(h, today);

    final sub = <String>[
      if (stats.current > 0) '${stats.current} ${stats.unit == 'weeks' ? 'week' : 'day'} streak'
      else 'No streak yet',
      if (h.freq == 'times') '${store.doneThisWeek(h)}/${h.timesPerWeek} this week',
      if (h.isCount) '$value/${h.target} ${h.unit}'.trim(),
    ];

    Widget trailing;
    if (h.archived) {
      trailing = const SizedBox.shrink();
    } else if (h.isCount) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 0 ? () => store.setValue(h, today, value - 1) : null),
        Builder(
          builder: (btn) => IconButton(
            icon: _CheckIcon(done: done, color: color, addIcon: Icons.add_circle_outline),
            onPressed: () {
              final reaches = !done && value + 1 >= h.target;
              store.setValue(h, today, value + 1);
              if (reaches) celebrate(btn);
            },
          ),
        ),
      ]);
    } else {
      trailing = Builder(
        builder: (btn) => IconButton(
          iconSize: 32,
          icon: _CheckIcon(done: done, color: color, addIcon: Icons.circle_outlined),
          onPressed: () {
            final becomesDone = !done;
            store.toggle(h, today);
            if (becomesDone) celebrate(btn);
          },
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: habitGlyph(h, color),
        ),
        title: Text(h.name,
            style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: Text(sub.join('  ·  ')),
        trailing: trailing,
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: h.id))),
      ),
    );
  }
}

/// Check mark that pops in with a springy scale when completed.
class _CheckIcon extends StatelessWidget {
  const _CheckIcon({required this.done, required this.color, required this.addIcon});
  final bool done;
  final Color color;
  final IconData addIcon;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.elasticOut,
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: done
          ? Icon(Icons.check_circle_rounded, key: const ValueKey('done'), color: color)
          : Icon(addIcon, key: const ValueKey('todo')),
    );
  }
}
