import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../data/journal_models.dart';
import '../data/journal_store.dart';
import '../services/journal_lock.dart';
import '../widgets/common.dart';
import '../widgets/fx.dart';
import 'journal_editor.dart';
import 'journal_media.dart';
import 'journal_pdf.dart';
import 'journal_settings.dart';

String _plain(String md) => md
    .replaceAll(RegExp(r'^\s*(#{1,6}|>|[-*]|\d+\.)\s+', multiLine: true), '')
    .replaceAll(RegExp(r'(\*\*|__|~~|\*|_)'), '')
    .replaceAll('\n', ' ')
    .trim();

void openEntry(BuildContext context, JournalEntry? e, {String? prompt, DateTime? date}) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => JournalEditor(entry: e, prompt: prompt, initialDate: date)));

class JournalHome extends StatefulWidget {
  const JournalHome({super.key});

  @override
  State<JournalHome> createState() => _JournalHomeState();
}

class _JournalHomeState extends State<JournalHome> {
  bool _calendar = false;
  bool _searching = false;
  String _query = '';
  String _filter = 'all';
  DateTime _day = DateTime.now();
  DateTime _focused = DateTime.now();
  late int _prompt = DateTime.now().difference(DateTime(DateTime.now().year)).inDays % writingPrompts.length;

  static const _filters = [
    ('all', 'All'),
    ('bookmarked', 'Bookmarked'),
    ('photo', 'Photos'),
    ('video', 'Videos'),
    ('audio', 'Audio'),
    ('drawing', 'Handwritten'),
    ('places', 'Places'),
  ];

  void _showInsights(BuildContext context, JournalStore j) {
    final s = j.insights();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your journal', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              StatGrid(minWidth: 140, children: [
                StatCard(label: 'Current streak', value: '${s.currentStreak} days', icon: Icons.local_fire_department_rounded, color: Colors.deepOrange),
                StatCard(label: 'Longest streak', value: '${s.longestStreak} days', icon: Icons.emoji_events_rounded),
                StatCard(label: 'Entries', value: '${s.entries}', icon: Icons.menu_book_rounded),
                StatCard(label: 'Words written', value: NumberFormat.decimalPattern().format(s.words), icon: Icons.edit_note_rounded),
                StatCard(label: 'Photos & drawings', value: '${s.photos}', icon: Icons.photo_outlined),
                StatCard(label: 'Voice & video', value: '${s.audios + s.videos}', icon: Icons.mic_none_rounded),
              ]),
              const SizedBox(height: 18),
              Text('Mood', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var m = 1; m <= 5; m++)
                  Column(children: [
                    Text(moodEmojis[m], style: const TextStyle(fontSize: 26)),
                    Text('${s.moodCounts[m]}', style: Theme.of(ctx).textTheme.titleSmall),
                  ]),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final j = context.watch<JournalStore>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final list = j.search(_query, filter: _filter);
    final insights = j.insights();
    final memories = j.memories();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openEntry(context, null),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New entry'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: revealAll([
            Row(children: [
              Expanded(child: Text('Journal', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
              IconButton(
                  tooltip: 'Search',
                  icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
                  onPressed: () => setState(() {
                        _searching = !_searching;
                        if (!_searching) _query = '';
                      })),
              IconButton(tooltip: 'Insights', icon: const Icon(Icons.insights_rounded), onPressed: () => _showInsights(context, j)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'export':
                      exportJournalPdf(context);
                    case 'settings':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalSettingsPage()));
                    case 'lock':
                      context.read<JournalLock>().lockNow();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'export', child: Text('Export journal as PDF')),
                  PopupMenuItem(value: 'settings', child: Text('Journal settings')),
                  PopupMenuItem(value: 'lock', child: Text('Lock journal now')),
                ],
              ),
            ]),
            if (_searching)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Search your journal', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            // streak / numbers
            Glass(
              onTap: () => _showInsights(context, j),
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.local_fire_department_rounded, color: insights.currentStreak > 0 ? Colors.deepOrange : cs.outline, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(insights.currentStreak == 0 ? 'Start your streak today' : '${insights.currentStreak}-day streak',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${insights.entries} entries · ${NumberFormat.decimalPattern().format(insights.words)} words',
                        style: tt.bodySmall),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
            // prompt
            if (!insights.writtenToday)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.lightbulb_outline_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Need an idea?', style: tt.labelLarge),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Another idea',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: () => setState(() => _prompt = (_prompt + 1) % writingPrompts.length),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(writingPrompts[_prompt],
                          key: ValueKey(_prompt), style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                        onPressed: () => openEntry(context, null, prompt: writingPrompts[_prompt]),
                        child: const Text('Write about it')),
                  ]),
                ),
              ),
            // on this day
            if (memories.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text('On this day', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              SizedBox(
                height: 112,
                child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
                  for (final e in memories)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 240,
                        child: Tilt(
                          child: Glass(
                            onTap: () => openEntry(context, e),
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${DateTime.now().year - e.date.year} year${DateTime.now().year - e.date.year == 1 ? '' : 's'} ago',
                                  style: tt.labelMedium?.copyWith(color: cs.primary)),
                              const SizedBox(height: 4),
                              Text(e.title.isNotEmpty ? e.title : _plain(e.body),
                                  maxLines: 3, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ],
            // filters + view switch
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('Timeline')),
                ButtonSegment(value: true, icon: Icon(Icons.calendar_month_outlined, size: 18), label: Text('Calendar')),
              ],
              selected: {_calendar},
              onSelectionChanged: (v) => setState(() => _calendar = v.first),
            ),
            const SizedBox(height: 10),
            if (_calendar) ..._calendarView(context, j) else ..._timeline(context, list),
          ])),
        ),
      ),
    );
  }

  List<Widget> _timeline(BuildContext context, List<JournalEntry> list) {
    if (list.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(36),
          child: Center(
            child: Text(_query.isNotEmpty || _filter != 'all' ? 'No entries match.' : 'Nothing here yet.\nTap "New entry" to write your first one.',
                textAlign: TextAlign.center),
          ),
        ),
      ];
    }
    final out = <Widget>[];
    String? month;
    for (final e in list) {
      final m = DateFormat('MMMM y').format(e.date);
      if (m != month) {
        month = m;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(m.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        ));
      }
      out.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: _EntryCard(e)));
    }
    return out;
  }

  List<Widget> _calendarView(BuildContext context, JournalStore j) {
    final dayEntries = j.on(_day);
    return [
      Card(
        child: TableCalendar<JournalEntry>(
          firstDay: DateTime(2000),
          lastDay: DateTime(2100),
          focusedDay: _focused,
          selectedDayPredicate: (d) => isSameDay(d, _day),
          eventLoader: (d) => j.on(d),
          startingDayOfWeek: StartingDayOfWeek.monday,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          onDaySelected: (s, f) => setState(() {
            _day = s;
            _focused = f;
          }),
          onPageChanged: (f) => _focused = f,
        ),
      ),
      const SizedBox(height: 12),
      if (dayEntries.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Column(children: [
              Text('No entry on ${DateFormat('d MMM').format(_day)}'),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: () => openEntry(context, null, date: DateTime(_day.year, _day.month, _day.day, DateTime.now().hour, DateTime.now().minute)),
                  child: const Text('Write one')),
            ]),
          ),
        ),
      for (final e in dayEntries) Padding(padding: const EdgeInsets.only(bottom: 10), child: _EntryCard(e)),
    ];
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.e);
  final JournalEntry e;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final thumbs = e.media.where((m) => m.kind == 'photo' || m.kind == 'drawing' || m.kind == 'video').take(3).toList();
    final snippet = _plain(e.body);
    return Tilt(
      strength: 0.35,
      child: Glass(
        onTap: () => openEntry(context, e),
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 46,
            child: Column(children: [
              Text(DateFormat('d').format(e.date), style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
              Text(DateFormat('EEE').format(e.date).toUpperCase(), style: tt.labelSmall),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(e.title.isNotEmpty ? e.title : (snippet.isEmpty ? 'Untitled' : snippet),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (e.mood > 0) Text(moodEmojis[e.mood], style: const TextStyle(fontSize: 18)),
                if (e.bookmarked) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.bookmark_rounded, size: 18, color: cs.primary)),
              ]),
              if (e.title.isNotEmpty && snippet.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                ),
              if (thumbs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 6, children: [for (final m in thumbs) MediaThumb(m, size: 56)]),
                ),
              if (e.hasPlace || e.has('audio') || e.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (e.hasPlace) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.place_rounded, size: 14), const SizedBox(width: 3), Text(e.place.isEmpty ? 'Location' : e.place, style: tt.labelSmall)]),
                    if (e.has('audio')) const Icon(Icons.mic_rounded, size: 14),
                    for (final t in e.tags.take(3)) Text('#$t', style: tt.labelSmall?.copyWith(color: cs.primary)),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
