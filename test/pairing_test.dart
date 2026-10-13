import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskme/sync/sync_net.dart';
import 'package:taskme/sync/sync_pair.dart';

void main() {
  late SyncServer server;
  late Completer<PairResult?> hubResult;
  var wrongPins = 0;

  Future<void> startHub(String pin) async {
    hubResult = Completer<PairResult?>();
    wrongPins = 0;
    server = SyncServer(
      deviceId: 'hub-id',
      onSocket: (ws, from) => ws.close(),
      onPairSocket: (ws, from) {
        PinPairing.hubSide(ws, pin: pin, hubId: 'hub-id', hubName: 'My laptop', onWrongPin: () => wrongPins++)
            .then((r) {
          if (!hubResult.isCompleted) hubResult.complete(r);
        });
      },
    );
    await server.start();
  }

  tearDown(() async => server.stop());

  test('PIN pairing: the right PIN gives both sides the same key and names', () async {
    await startHub('482913');
    final ws = await connectPairSocket('127.0.0.1', server.port);
    final client = await PinPairing.clientSide(ws, pin: '482913', myId: 'phone-id', myName: 'My phone');
    final hub = await hubResult.future.timeout(const Duration(seconds: 20));

    expect(client, isNotNull);
    expect(hub, isNotNull);
    expect(client!.key, hub!.key); // same permanent key on both devices
    expect(client.key.length, greaterThan(40));
    expect(client.peerId, 'hub-id');
    expect(client.peerName, 'My laptop');
    expect(hub.peerId, 'phone-id');
    expect(hub.peerName, 'My phone');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('PIN pairing: a wrong PIN is refused on both sides and counted', () async {
    await startHub('482913');
    final ws = await connectPairSocket('127.0.0.1', server.port);
    final client = await PinPairing.clientSide(ws, pin: '000000', myId: 'phone-id', myName: 'My phone');
    final hub = await hubResult.future.timeout(const Duration(seconds: 20));
    expect(client, isNull);
    expect(hub, isNull);
    expect(wrongPins, 1);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('PIN pairing: two pairings never produce the same key', () async {
    await startHub('111222');
    final ws1 = await connectPairSocket('127.0.0.1', server.port);
    final c1 = await PinPairing.clientSide(ws1, pin: '111222', myId: 'a', myName: 'A');
    await hubResult.future.timeout(const Duration(seconds: 20));
    hubResult = Completer<PairResult?>();
    final ws2 = await connectPairSocket('127.0.0.1', server.port);
    final c2 = await PinPairing.clientSide(ws2, pin: '111222', myId: 'b', myName: 'B');
    expect(c1, isNotNull);
    expect(c2, isNotNull);
    expect(c1!.key, isNot(c2!.key));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('the computer answers a phone looking for the PIN or for a QR token, but not for strangers', () async {
    server = SyncServer(deviceId: 'hub-xyz', onSocket: (ws, from) => ws.close());
    await server.start();
    server.answerIds.add('PIN');
    server.answerIds.add('tok3n1234');

    expect((await discoverDesktop('PIN'))?.$2, server.port);
    expect((await discoverDesktop('tok3n1234'))?.$2, server.port);
    expect((await discoverDesktop('hub-xyz'))?.$2, server.port);
    expect(await discoverDesktop('other', timeout: const Duration(milliseconds: 700)), isNull);

    server.answerIds.remove('PIN'); // pairing closed: the PIN no longer answers
    expect(await discoverDesktop('PIN', timeout: const Duration(milliseconds: 700)), isNull);
    expect(server.running, isTrue);
    expect(Platform.isWindows || Platform.isLinux || Platform.isMacOS, isTrue);
  });
}
