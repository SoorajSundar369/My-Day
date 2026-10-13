import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// What a successful pairing gives each side.
class PairResult {
  PairResult({required this.peerId, required this.peerName, required this.key});
  final String peerId;
  final String peerName;

  /// The permanent 256-bit key for this pair of devices (base64).
  final String key;
}

/// Pairing with a short code (PIN) instead of a QR code.
///
/// A 6-digit number is too short to be a key, so it is never used as one. Instead
/// the two devices make a fresh shared secret (X25519) and then prove to each other
/// that they both know the PIN, using it only as a password check on that exchange.
/// Someone listening on the Wi-Fi learns nothing; to cheat they would have to sit
/// in the middle of the exchange and still guess the PIN, and every guess is slow.
class PinPairing {
  static final _x25519 = X25519();
  static final _mac = Hmac.sha256();
  static const _iterations = 60000;

  static String _b64(List<int> b) => base64Encode(b);

  static Future<List<int>> _transcriptHash(String clientPub, String hubPub) async =>
      (await Sha256().hash(utf8.encode('$clientPub|$hubPub'))).bytes;

  static Future<SecretKey> _pinKey(String pin, List<int> salt) =>
      Pbkdf2(macAlgorithm: _mac, iterations: _iterations, bits: 256).deriveKeyFromPassword(password: pin, nonce: salt);

  static Future<List<int>> _tag(SecretKey key, String role, String clientPub, String hubPub) async =>
      (await _mac.calculateMac(utf8.encode('$role|$clientPub|$hubPub'), secretKey: key)).bytes;

  static Future<String> _finalKey(List<int> shared, List<int> salt) async {
    final k = await Hkdf(hmac: _mac, outputLength: 32)
        .deriveKey(secretKey: SecretKey(shared), nonce: salt, info: utf8.encode('myday-key-v1'));
    return _b64(await k.extractBytes());
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  static Future<Map<String, dynamic>?> _next(StreamIterator<dynamic> it) async {
    try {
      if (!await it.moveNext().timeout(const Duration(seconds: 15))) return null;
      final d = it.current;
      return d is String ? jsonDecode(d) as Map<String, dynamic> : null;
    } catch (_) {
      return null;
    }
  }

  /// The computer's side. Returns null if the other side did not know the PIN.
  /// [onWrongPin] is called for every failed attempt so the caller can limit tries.
  static Future<PairResult?> hubSide(
    WebSocket ws, {
    required String pin,
    required String hubId,
    required String hubName,
    void Function()? onWrongPin,
  }) async {
    final it = StreamIterator<dynamic>(ws);
    try {
      final hello = await _next(it);
      if (hello == null || hello['t'] != 'pub') return null;
      final clientPub = hello['pub'] as String;

      final kp = await _x25519.newKeyPair();
      final hubPub = _b64((await kp.extractPublicKey()).bytes);
      ws.add(jsonEncode({'t': 'pub', 'pub': hubPub, 'id': hubId, 'name': hubName}));

      final shared = await (await _x25519.sharedSecretKey(
        keyPair: kp,
        remotePublicKey: SimplePublicKey(base64Decode(clientPub), type: KeyPairType.x25519),
      )).extractBytes();
      final salt = await _transcriptHash(clientPub, hubPub);
      final pinKey = await _pinKey(pin, salt);

      final auth = await _next(it);
      if (auth == null || auth['t'] != 'auth') return null;
      final expected = await _tag(pinKey, 'client', clientPub, hubPub);
      if (!_same(base64Decode(auth['mac'] as String), expected)) {
        onWrongPin?.call();
        ws.add(jsonEncode({'t': 'fail'}));
        return null;
      }
      final mine = await _tag(pinKey, 'hub', clientPub, hubPub);
      final key = await _finalKey(shared, salt);
      ws.add(jsonEncode({'t': 'auth', 'mac': _b64(mine)}));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return PairResult(peerId: hello['id'] as String, peerName: (hello['name'] as String?) ?? 'My phone', key: key);
    } catch (_) {
      return null;
    } finally {
      await it.cancel();
      try {
        await ws.close();
      } catch (_) {}
    }
  }

  /// The phone's side. Returns null if the PIN was wrong or the computer did not answer.
  static Future<PairResult?> clientSide(
    WebSocket ws, {
    required String pin,
    required String myId,
    required String myName,
  }) async {
    final it = StreamIterator<dynamic>(ws);
    try {
      final kp = await _x25519.newKeyPair();
      final clientPub = _b64((await kp.extractPublicKey()).bytes);
      ws.add(jsonEncode({'t': 'pub', 'pub': clientPub, 'id': myId, 'name': myName}));

      final hello = await _next(it);
      if (hello == null || hello['t'] != 'pub') return null;
      final hubPub = hello['pub'] as String;

      final shared = await (await _x25519.sharedSecretKey(
        keyPair: kp,
        remotePublicKey: SimplePublicKey(base64Decode(hubPub), type: KeyPairType.x25519),
      )).extractBytes();
      final salt = await _transcriptHash(clientPub, hubPub);
      final pinKey = await _pinKey(pin, salt);

      ws.add(jsonEncode({'t': 'auth', 'mac': _b64(await _tag(pinKey, 'client', clientPub, hubPub))}));
      final reply = await _next(it);
      if (reply == null || reply['t'] != 'auth') return null; // wrong PIN: the computer answers 'fail'
      final expected = await _tag(pinKey, 'hub', clientPub, hubPub);
      if (!_same(base64Decode(reply['mac'] as String), expected)) return null;
      return PairResult(
        peerId: hello['id'] as String,
        peerName: (hello['name'] as String?) ?? 'My computer',
        key: await _finalKey(shared, salt),
      );
    } catch (_) {
      return null;
    } finally {
      await it.cancel();
      try {
        await ws.close();
      } catch (_) {}
    }
  }
}
