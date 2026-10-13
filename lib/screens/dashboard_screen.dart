import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/data_store.dart';
import '../data/habit_store.dart';
import '../data/money_store.dart';
import '../services/settings_service.dart';
import '../widgets/fx.dart';
import '../widgets/task_tile.dart';
import 'files_screen.dart';
import 'notes_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final store = context.watch<DataStore>();
    final habits = context.watch<HabitStore>();
    final money = context.watch<MoneyStore>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final tt = Theme.of(context).textTheme;

    final open = store.tasks.where((t) => !t.done).toList();
    final overdue = open.where((t) => t.due != null && t.due!.isBefore(now)).toList();
    final todays =
        open.where((t) => t.due != null && !t.due!.isBefore(today) && t.due!.isBefore(tomorrow)).toList()
          ..sort((a, b) => a.due!.compareTo(b.due!));
    final upcoming = open.where((t) => t.due != null && !t.due!.isBefore(tomorrow)).toList()
      ..sort((a, b) => a.due!.compareTo(b.due!));
    final doneToday = store.tasks
        .where((t) => t.done && t.due != null && !t.due!.isBefore(today) && t.due!.isBefore(tomorrow))
        .length;
    final totalToday = todays.length + doneToday;
    final pinned = store.notes.where((n) => n.pinned).toList();
    final recent = [...store.visibleFiles]..sort((a, b) => b.created.compareTo(a.created));

    final hDue = habits.dueToday().length;
    final hDone = habits.doneTodayCount();
    final spent = money.spentInMonth(now);
    final budget = money.budgets[''];

    var i = 0;
    Widget header(String t, int tab) => Reveal(
          index: i++,
          child: Padding(
            padding: const EdgeInsets.only(top: 26, bottom: 10),
            child: Row(children: [
              Text(t, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: () => onNavigate(tab), child: const Text('See all')),
            ]),
          ),
        );
    Widget row(Widget w) =>
        Reveal(index: i++, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: w));

    final summaryCards = <Widget>[
      _Summary(
        title: 'Due today',
        onTap: () => onNavigate(1),
        ring: AnimatedRing(
            value: totalToday == 0 ? 0 : doneToday / totalToday,
            size: 78,
            child: Text('$doneToday/$totalToday', style: const TextStyle(fontWeight: FontWeight.w700))),
        lines: [
          '${todays.length} to do',
          if (overdue.isNotEmpty) '${overdue.length} overdue',
        ],
      ),
      _Summary(
        title: 'Habits today',
        onTap: () => onNavigate(2),
        ring: AnimatedRing(
          value: hDue == 0 ? 0 : hDone / hDue,
          size: 78,
          colors: const [Color(0xFFFF9A3C), Color(0xFFFF4E6A)],
          child: Text(hDue == 0 ? '–' : '$hDone/$hDue', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        lines: [hDue == 0 ? 'Nothing scheduled' : '${hDue - hDone} left today'],
      ),
      _Summary(
        title: 'Spent this month',
        onTap: () => onNavigate(3),
        ring: AnimatedRing(
          value: budget == null ? 0 : (spent / budget).clamp(0.0, 1.0),
          size: 78,
          colors: const [Color(0xFF34D399), Color(0xFF0EA5E9)],
          child: Icon(Icons.account_balance_wallet_rounded,
              size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        countValue: spent,
        countFormat: money.fmt,
        lines: [budget == null ? 'No budget set' : 'of ${money.fmt(budget)}'],
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
          Reveal(
            index: i++,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
                  style: tt.labelMedium?.copyWith(
                      letterSpacing: 1.6, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              GradientText(s.greeting(), style: tt.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 760 ? 3 : (c.maxWidth >= 480 ? 2 : 1);
            final w = (c.maxWidth - (cols - 1) * 14) / cols;
            return Wrap(spacing: 14, runSpacing: 14, children: [
              for (final card in summaryCards)
                SizedBox(width: w, child: Reveal(index: i++, child: Tilt(child: card))),
            ]);
          }),
          if (overdue.isNotEmpty) ...[
            header('Overdue', 1),
            for (final t in overdue.take(5)) row(TaskTile(t)),
          ],
          header('Today', 1),
          if (todays.isEmpty) row(const Text('Nothing due today 🎉')),
          for (final t in todays) row(TaskTile(t)),
          if (upcoming.isNotEmpty) ...[
            header('Coming up', 1),
            for (final t in upcoming.take(4)) row(TaskTile(t)),
          ],
          if (pinned.isNotEmpty) ...[
            header('Pinned notes', 5),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                children: [
                  for (final n in pinned)
                    Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(width: 210, child: Tilt(child: NoteCard(n)))),
                ],
              ),
            ),
          ],
          if (recent.isNotEmpty) ...[
            header('Recent files', 6),
            for (final f in recent.take(3))
              row(Card(
                child: ListTile(
                  leading: Icon(fileIcon(f)),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(fmtSize(f.size)),
                  onTap: () => openVaultFile(context, f),
                ),
              )),
          ],
        ]),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.title,
    required this.ring,
    required this.lines,
    required this.onTap,
    this.countValue,
    this.countFormat,
  });

  final String title;
  final Widget ring;
  final List<String> lines;
  final VoidCallback onTap;
  final double? countValue;
  final String Function(double)? countFormat;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Glass(
      onTap: onTap,
      blur: true,
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        ring,
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            if (countValue != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedCount(
                    value: countValue!,
                    format: countFormat!,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
            for (final l in lines)
              Text(l,
                  style: tt.bodySmall?.copyWith(color: l.contains('overdue') ? cs.error : cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}
