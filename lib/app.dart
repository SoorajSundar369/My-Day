import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'quick/quick_add.dart';
import 'screens/home_shell.dart';
import 'widgets/fx.dart';
import 'screens/lock_screen.dart';
import 'screens/setup_screen.dart';
import 'services/lock_controller.dart';
import 'services/settings_service.dart';

class TaskmeApp extends StatelessWidget {
  const TaskmeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final lock = context.watch<LockController>();
    final quick = context.watch<QuickAddController>();
    return MaterialApp(
      title: s.appName,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AuroraBackground(child: child ?? const SizedBox.shrink()),
      themeMode: s.themeMode,
      theme: buildTheme(s.accent, Brightness.light),
      darkTheme: buildTheme(s.accent, Brightness.dark),
      home: Listener(
        // Any mouse/touch/key activity resets the inactivity timer.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => lock.touch(),
        onPointerMove: (_) => lock.touch(),
        onPointerSignal: (_) => lock.touch(),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 650),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => AnimatedBuilder(
            animation: anim,
            child: child,
            builder: (context, child) {
              final t = anim.value;
              return Opacity(
                opacity: t,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX((1 - t) * 0.35)
                    ..scale(0.9 + 0.1 * t),
                  child: child,
                ),
              );
            },
          ),
          child: quick.action != null && s.setupDone
              ? const QuickAddScreen(key: ValueKey('quick'))
              : !s.setupDone
              ? const SetupScreen(key: ValueKey('setup'))
              : lock.locked
                  ? const LockScreen(key: ValueKey('lock'))
                  : const HomeShell(key: ValueKey('home')),
        ),
      ),
    );
  }
}
