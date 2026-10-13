import 'dart:async';

import 'package:flutter/foundation.dart';

import 'settings_service.dart';

/// Tracks whether the app is locked and handles inactivity auto-lock.
class LockController extends ChangeNotifier {
  LockController(this.settings) {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  final SettingsService settings;
  late final Timer _timer;
  bool locked = true;

  /// Called after a successful unlock (plays the unlock sound).
  VoidCallback? onUnlocked;
  DateTime _last = DateTime.now();

  void touch() => _last = DateTime.now();

  void lock() {
    if (!settings.setupDone || locked) return;
    locked = true;
    notifyListeners();
  }

  void unlock() {
    locked = false;
    touch();
    onUnlocked?.call();
    notifyListeners();
  }

  void _check() {
    final mins = settings.autoLockMinutes;
    if (mins > 0 && !locked && DateTime.now().difference(_last).inMinutes >= mins) lock();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
