import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const accentChoices = <Color>[
  Color(0xFF4F6BED),
  Color(0xFF009688),
  Color(0xFFE91E63),
  Color(0xFFFF7043),
  Color(0xFF7E57C2),
  Color(0xFF43A047),
  Color(0xFF00A3E0),
  Color(0xFFB8860B),
];

/// All user settings + PIN / security-question handling.
class SettingsService extends ChangeNotifier {
  late SharedPreferences _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  // ---- profile ----
  bool get setupDone => _p.getBool('setupDone') ?? false;
  String get name => _p.getString('name') ?? '';
  String get nickname => _p.getString('nickname') ?? '';
  String get appName => _p.getString('appName') ?? 'MyDay';

  /// Which name the greeting uses: 'nickname' or 'name'.
  String get callMeBy => _p.getString('callMeBy') ?? 'nickname';
  String get greetingTemplate => _p.getString('greeting') ?? 'Good {time}, {call}';
  String get callName {
    final n = callMeBy == 'name' ? name : nickname;
    return n.isEmpty ? name : n;
  }

  String greeting() {
    final h = DateTime.now().hour;
    final time = h < 12 ? 'morning' : (h < 17 ? 'afternoon' : 'evening');
    return greetingTemplate
        .replaceAll('{time}', time)
        .replaceAll('{call}', callName)
        .replaceAll('{name}', name)
        .replaceAll('{nick}', nickname);
  }

  // ---- appearance ----
  ThemeMode get themeMode => ThemeMode.values[_p.getInt('themeMode') ?? 0];
  int get accentIndex => _p.getInt('accent') ?? 0;
  Color get accent => accentChoices[accentIndex.clamp(0, accentChoices.length - 1)];

  // ---- behaviour ----
  int get autoLockMinutes => _p.getInt('autoLock') ?? 5; // 0 = never
  bool get lockOnTray => _p.getBool('lockOnTray') ?? true;
  bool get minimizeToTray => _p.getBool('tray') ?? true;
  bool get startWithWindows => _p.getBool('startup') ?? false;
  bool get hideNotifContent => _p.getBool('hideNotif') ?? false;
  /// Animation strength: 0 off, 1 subtle, 2 balanced, 3 bold.
  int get motionLevel => _p.getInt('motion') ?? (Platform.isAndroid ? 2 : 3);
  // Fingerprint is per device (never synced): it depends on this phone's sensor.
  bool get bioApp => _p.getBool('bioApp') ?? false;
  bool get bioJournal => _p.getBool('bioJournal') ?? false;
  bool get bioOffered => _p.getBool('bioOffered') ?? false;
  bool get soundsOn => _p.getBool('sounds') ?? true;
  int get weekStart => _p.getInt('weekStart') ?? 1; // 1 = Monday, 7 = Sunday
  String get currency => _p.getString('currency') ?? '₹';
  int get snoozeMinutes => _p.getInt('snooze') ?? 10;

  // ---- security ----
  String get securityQuestion => _p.getString('secQ') ?? '';
  String get securityHint => _p.getString('secHint') ?? '';
  int get failedAttempts => _p.getInt('failed') ?? 0;

  /// Settings that follow you to your other device. PIN, security question,
  /// theme and animation settings stay per device.
  static const syncedKeys = {
    'name', 'nickname', 'appName', 'callMeBy', 'greeting', 'currency', 'weekStart',
    // One PIN, one security question and one journal lock for all your devices.
    'setupDone', 'pinHash', 'pinSalt', 'secQ', 'secHint', 'secSalt', 'secHash',
    'journalSetup', 'journalMode', 'journalPinLen', 'journalPinHash', 'journalPinSalt',
    'journalGrace', 'journalRemind',
  };
  /// Settings that only travel when something *changes* them (or to a brand-new device), never as a
  /// side effect of two already-set-up devices meeting: otherwise one device's PIN could silently replace the other's.
  static const securityKeys = {
    'setupDone', 'pinHash', 'pinSalt', 'secQ', 'secHint', 'secSalt', 'secHash',
    'journalSetup', 'journalMode', 'journalPinLen', 'journalPinHash', 'journalPinSalt',
  };
  static const _boolKeys = {'setupDone', 'journalSetup'};
  static const _intKeys = {'weekStart', 'journalPinLen', 'journalGrace'};

  /// The settings that make a freshly paired device "already set up".
  static const identityKeys = {
    'name', 'nickname', 'appName', 'callMeBy', 'greeting', 'currency', 'weekStart', 'setupDone',
    'pinHash', 'pinSalt', 'secQ', 'secHint', 'secSalt', 'secHash',
    'journalSetup', 'journalMode', 'journalPinLen', 'journalPinHash', 'journalPinSalt', 'journalGrace', 'journalRemind',
  };

  void _mirror(String key, Object value) {
    if (syncedKeys.contains(key)) onSyncedChange?.call(key, '$value');
  }

  /// Set by the sync service so a local change of a synced setting is sent on.
  void Function(String key, String value)? onSyncedChange;

  Future<void> set(String key, Object value) async {
    switch (value) {
      case bool v:
        await _p.setBool(key, v);
      case int v:
        await _p.setInt(key, v);
      case String v:
        await _p.setString(key, v);
    }
    if (syncedKeys.contains(key)) onSyncedChange?.call(key, '$value');
    notifyListeners();
  }

  /// Current value of a synced setting as text (null if never set).
  String? syncedValue(String key) {
    final v = _p.get(key);
    return v == null ? null : '$v';
  }

  /// Applies a setting that arrived from the other device (does not echo back).
  Future<void> applyRemote(String key, String value) async {
    if (!syncedKeys.contains(key)) return;
    if (_intKeys.contains(key)) {
      await _p.setInt(key, int.tryParse(value) ?? 0);
    } else if (_boolKeys.contains(key)) {
      await _p.setBool(key, value == 'true');
    } else {
      await _p.setString(key, value);
    }
    if (key == 'pinHash') await _p.setInt('failed', 0);
    notifyListeners();
  }

  Future<void> saveProfile({required String name, required String nickname}) async {
    await _p.setString('name', name);
    await _p.setString('nickname', nickname);
    onSyncedChange?.call('name', name);
    onSyncedChange?.call('nickname', nickname);
    notifyListeners();
  }

  Future<void> completeSetup() => set('setupDone', true);

  // ---- PIN ----
  String _hash(String value, String salt) {
    Uint8List bytes = Uint8List.fromList(utf8.encode('$salt:$value'));
    for (var i = 0; i < 20000; i++) {
      bytes = Uint8List.fromList(sha256.convert(bytes).bytes);
    }
    return base64Encode(bytes);
  }

  String _newSalt() =>
      base64Encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));

  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    await _p.setString('pinSalt', salt);
    final hash = _hash(pin, salt);
    await _p.setString('pinHash', hash);
    await _p.setInt('failed', 0);
    _mirror('pinSalt', salt);
    _mirror('pinHash', hash);
    notifyListeners();
  }

  bool verifyPin(String pin) {
    final ok = _hash(pin, _p.getString('pinSalt') ?? '') == _p.getString('pinHash');
    _p.setInt('failed', ok ? 0 : failedAttempts + 1);
    return ok;
  }

  Future<void> setSecurity({
    required String question,
    required String answer,
    required String hint,
  }) async {
    final salt = _newSalt();
    await _p.setString('secQ', question);
    await _p.setString('secHint', hint);
    await _p.setString('secSalt', salt);
    final hash = _hash(_norm(answer), salt);
    await _p.setString('secHash', hash);
    _mirror('secQ', question);
    _mirror('secHint', hint);
    _mirror('secSalt', salt);
    _mirror('secHash', hash);
    notifyListeners();
  }

  String _norm(String a) => a.trim().toLowerCase();

  bool verifyAnswer(String answer) =>
      _hash(_norm(answer), _p.getString('secSalt') ?? '') == _p.getString('secHash');

  Future<void> resetFailed() => _p.setInt('failed', 0);

  /// Checks the app PIN without counting a failed attempt.
  bool checkPin(String pin) => _hash(pin, _p.getString('pinSalt') ?? '') == _p.getString('pinHash');

  // ---- journal lock ----
  bool get journalSetupDone => _p.getBool('journalSetup') ?? false;

  /// 'app' = the journal opens with the app PIN, 'own' = it has its own PIN.
  String get journalMode => _p.getString('journalMode') ?? 'app';
  int get journalPinLen => _p.getInt('journalPinLen') ?? 4;

  /// How long (minutes) the journal stays unlocked after leaving it. 0 = ask every time.
  int get journalGraceMinutes => _p.getInt('journalGrace') ?? 0;

  /// Daily "time to write" reminder as "HH:mm", or empty when off.
  String get journalReminder => _p.getString('journalRemind') ?? '';

  bool checkJournalPin(String pin) {
    if (journalMode == 'app') return checkPin(pin);
    return _hash(pin, _p.getString('journalPinSalt') ?? '') == _p.getString('journalPinHash');
  }

  Future<void> completeJournalSetup({required String mode, int length = 4, String? pin}) async {
    await _p.setString('journalMode', mode);
    _mirror('journalMode', mode);
    if (mode == 'own' && pin != null) {
      await setJournalPin(pin, length);
    } else {
      await _p.setInt('journalPinLen', 4);
      _mirror('journalPinLen', 4);
    }
    await _p.setBool('journalSetup', true);
    _mirror('journalSetup', true);
    notifyListeners();
  }

  Future<void> setJournalPin(String pin, int length) async {
    final salt = _newSalt();
    final hash = _hash(pin, salt);
    await _p.setString('journalPinSalt', salt);
    await _p.setString('journalPinHash', hash);
    await _p.setInt('journalPinLen', length);
    _mirror('journalPinSalt', salt);
    _mirror('journalPinHash', hash);
    _mirror('journalPinLen', length);
    notifyListeners();
  }

  // ---- backup support ----
  Map<String, dynamic> exportAll() => {for (final k in _p.getKeys()) k: _p.get(k)};

  Future<void> importAll(Map<String, dynamic> m) async {
    await _p.clear();
    for (final e in m.entries) {
      final v = e.value;
      if (v is bool) {
        await _p.setBool(e.key, v);
      } else if (v is int) {
        await _p.setInt(e.key, v);
      } else if (v is String) {
        await _p.setString(e.key, v);
      }
    }
    notifyListeners();
  }
}
