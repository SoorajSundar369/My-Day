import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Fingerprint unlock (phones). The PIN always stays as the backup, because a fingerprint
/// can fail or be removed. A successful fingerprint only *unlocks*; no secret depends on it.
class BiometricService {
  BiometricService([this._auth]);

  final LocalAuthentication? _auth;
  LocalAuthentication get _a => _auth ?? LocalAuthentication();

  /// Only phones for now (Windows Hello is not used).
  static bool get platformSupported => Platform.isAndroid;

  /// True when this phone has a fingerprint (or similar) sensor with something enrolled.
  Future<bool> available() async {
    if (!platformSupported) return false;
    try {
      if (!await _a.isDeviceSupported()) return false;
      return (await _a.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system fingerprint prompt. False if cancelled, failed or unavailable.
  Future<bool> authenticate(String reason, {String closeLabel = 'Use PIN'}) async {
    if (!platformSupported) return false;
    try {
      return await _a.authenticate(
        localizedReason: reason,
        authMessages: [AndroidAuthMessages(signInTitle: 'MyDay', cancelButton: closeLabel)],
        biometricOnly: true, // never fall back to the phone's own PIN/pattern: ours is the backup
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
