import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM encryption for every message sent between two paired devices.
/// Wire format of one message: nonce (12 bytes) + ciphertext + auth tag (16 bytes).
class SyncCipher {
  SyncCipher(List<int> keyBytes) : _key = SecretKey(keyBytes);

  factory SyncCipher.fromBase64(String b64) => SyncCipher(base64Decode(b64));

  final SecretKey _key;
  static final _algo = AesGcm.with256bits();

  /// A fresh random 256-bit key, base64 encoded (shown in the pairing QR code).
  static String generateKey() {
    final rnd = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  Future<Uint8List> encrypt(List<int> plain) async {
    final box = await _algo.encrypt(plain, secretKey: _key);
    return Uint8List.fromList(box.concatenation());
  }

  /// Returns null if the data was not encrypted with this key or was tampered with.
  Future<Uint8List?> decrypt(List<int> data) async {
    try {
      final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
      return Uint8List.fromList(await _algo.decrypt(box, secretKey: _key));
    } catch (_) {
      return null;
    }
  }
}
