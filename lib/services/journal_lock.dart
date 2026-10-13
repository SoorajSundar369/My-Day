import 'package:flutter/foundation.dart';

import 'settings_service.dart';

/// Keeps track of whether the journal is currently unlocked.
///
/// While you are inside the journal it stays open. After you leave, it asks for the PIN
/// again unless you chose a grace period in Settings (up to 2 hours).
class JournalLock extends ChangeNotifier {
  JournalLock(this.settings);

  final SettingsService settings;
  DateTime? _graceUntil;
  bool _open = false;
  int failedAttempts = 0;

  bool get isOpen => _open;

  /// True when the PIN must be entered to get in.
  bool get needsPin {
    if (_open) return false;
    final g = _graceUntil;
    return !(g != null && DateTime.now().isBefore(g));
  }

  /// Checks the PIN. On success the journal opens.
  bool tryPin(String pin) {
    if (settings.checkJournalPin(pin)) {
      markUnlocked();
      return true;
    }
    failedAttempts++;
    notifyListeners();
    return false;
  }

  void markUnlocked() {
    _open = true;
    failedAttempts = 0;
    final m = settings.journalGraceMinutes;
    _graceUntil = m > 0 ? DateTime.now().add(Duration(minutes: m)) : null;
    notifyListeners();
  }

  /// Called when you leave the journal tab. The grace period (if any) keeps running.
  void leave() {
    _open = false;
  }

  /// Locks immediately, ignoring any grace period (used when the whole app locks).
  void lockNow() {
    _open = false;
    _graceUntil = null;
    notifyListeners();
  }
}
