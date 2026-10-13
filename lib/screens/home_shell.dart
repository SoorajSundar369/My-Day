import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/biometric_service.dart';
import '../services/lock_controller.dart';
import '../services/settings_service.dart';
import '../sync/sync_screen.dart';
import '../widgets/fx.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import '../journal/journal_gate.dart';
import 'files_screen.dart';
import 'habits_screen.dart';
import 'money_screen.dart';
import 'notes_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

/// Responsive shell: glass side rail on wide windows, floating bar on phones.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerBiometric());
  }

  /// Once, on a phone with a fingerprint sensor: "use your fingerprint instead of the PIN?"
  Future<void> _offerBiometric() async {
    final s = context.read<SettingsService>();
    final bio = context.read<BiometricService>();
    if (!BiometricService.platformSupported || s.bioOffered || s.bioApp) return;
    if (!await bio.available() || !mounted) return;
    await s.set('bioOffered', true); // ask only once; Settings has the switch
    var forApp = true, forJournal = true;
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Icons.fingerprint, size: 40),
          title: const Text('Use your fingerprint?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Unlock MyDay by touching the sensor instead of typing your PIN. Your PIN still works as a backup.',
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            SwitchListTile(
                contentPadding: EdgeInsets.zero, title: const Text('Unlock the app'), value: forApp, onChanged: (v) => setState(() => forApp = v)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Open the journal'),
                value: forJournal,
                onChanged: (v) => setState(() => forJournal = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn on')),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final ok = await bio.authenticate('Touch the sensor to turn this on', closeLabel: 'Cancel');
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not confirm your fingerprint. You can try again in Settings.')));
      return;
    }
    await s.set('bioApp', forApp);
    await s.set('bioJournal', forJournal);
  }

  static const _items = [
    (Icons.dashboard_outlined, Icons.dashboard_rounded, 'Home'),
    (Icons.check_circle_outline, Icons.check_circle_rounded, 'Tasks'),
    (Icons.local_fire_department_outlined, Icons.local_fire_department_rounded, 'Habits'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Money'),
    (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Journal'),
    (Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded, 'Notes'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Files'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Calendar'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  /// On narrow screens only the first [_barCount] fit in the bar; the rest go under "More".
  static const _barCount = 5;

  Widget _page() => switch (_index) {
        0 => DashboardScreen(onNavigate: _go),
        1 => const TasksScreen(),
        2 => const HabitsScreen(),
        3 => const MoneyScreen(),
        4 => const JournalGate(),
        5 => const NotesScreen(),
        6 => const FilesScreen(),
        7 => const CalendarScreen(),
        _ => const SettingsScreen(),
      };

  void _go(int i) => setState(() => _index = i);

  void _more() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          for (var i = _barCount; i < _items.length; i++)
            ListTile(
              leading: Icon(_items[i].$1),
              title: Text(_items[i].$3),
              selected: _index == i,
              onTap: () {
                Navigator.pop(ctx);
                _go(i);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _switcher(Motion m) => AnimatedSwitcher(
        duration: m.ms(520),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final isIncoming = child.key == ValueKey(_index);
          return AnimatedBuilder(
            animation: anim,
            child: child,
            builder: (context, child) {
              final t = anim.value;
              final side = isIncoming ? 1.0 : -1.0;
              final matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0009)
                ..translate(side * (1 - t) * 60 * m.depth, 0.0, -(1 - t) * 80 * m.depth)
                ..rotateY(side * (1 - t) * 0.22 * m.depth);
              return Opacity(
                  opacity: t, child: Transform(alignment: Alignment.center, transform: matrix, child: child));
            },
          );
        },
        child: KeyedSubtree(key: ValueKey(_index), child: _page()),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final s = context.watch<SettingsService>();
    final m = Motion.of(context);
    final appBar = AppBar(
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!wide) ...[
          ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/icon.png', width: 30, height: 30)),
          const SizedBox(width: 10),
        ],
        GradientText(s.appName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ]),
      actions: [
        const SyncButton(),
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search_rounded),
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
        ),
        IconButton(
          tooltip: 'Lock now',
          icon: const Icon(Icons.lock_outline_rounded),
          onPressed: () => context.read<LockController>().lock(),
        ),
        const SizedBox(width: 8),
      ],
    );

    final shell = _build(context, wide, appBar, m);
    return SyncListeners(child: shell);
  }

  Widget _build(BuildContext context, bool wide, AppBar appBar, Motion m) {
    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 0, 16),
            child: _SideRail(
              index: _index,
              items: _items,
              onSelect: _go,
              onLock: () => context.read<LockController>().lock(),
            ),
          ),
          Expanded(child: _switcher(m)),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: _switcher(m),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: _FloatingBar(
          index: _index < _barCount ? _index : _barCount,
          items: [..._items.take(_barCount), (Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More')],
          onSelect: (i) => i == _barCount ? _more() : _go(i),
        ),
      )),
    );
  }
}

typedef _NavDef = (IconData, IconData, String);

class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
        boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6))],
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.index, required this.items, required this.onSelect, required this.onLock});
  final int index;
  final List<_NavDef> items;
  final ValueChanged<int> onSelect;
  final VoidCallback onLock;

  static const itemH = 74.0;

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    final cs = Theme.of(context).colorScheme;
    return Glass(
      blur: true,
      radius: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: SizedBox(
        width: 72,
        child: Column(children: [
          SizedBox(
            height: itemH * items.length,
            child: Stack(children: [
              AnimatedPositioned(
                duration: m.ms(520),
                curve: Curves.easeOutBack,
                top: index * itemH + 3,
                left: 0,
                right: 0,
                height: itemH - 8,
                child: const _Pill(),
              ),
              Column(children: [
                for (var i = 0; i < items.length; i++)
                  SizedBox(
                    height: itemH,
                    child: _NavButton(
                      icon: i == index ? items[i].$2 : items[i].$1,
                      label: items[i].$3,
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ]),
            ]),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Lock now',
            icon: Icon(Icons.lock_outline_rounded, color: cs.onSurfaceVariant),
            onPressed: onLock,
          ),
        ]),
      ),
    );
  }
}

class _FloatingBar extends StatelessWidget {
  const _FloatingBar({required this.index, required this.items, required this.onSelect});
  final int index;
  final List<_NavDef> items;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    final n = items.length;
    return Glass(
      blur: true,
      radius: 30,
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 62,
        child: Stack(children: [
          AnimatedAlign(
            duration: m.ms(520),
            curve: Curves.easeOutBack,
            alignment: Alignment(-1 + 2 * index / (n - 1), 0),
            child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: const Padding(padding: EdgeInsets.all(2), child: _Pill())),
          ),
          Row(children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: _NavButton(
                  icon: i == index ? items[i].$2 : items[i].$1,
                  label: items[i].$3,
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? Colors.white : cs.onSurfaceVariant;
    return PressScale(
      onTap: onTap,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedScale(
            scale: selected ? 1.15 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color)),
        ]),
      ),
    );
  }
}
