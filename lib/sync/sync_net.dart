import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'sync_session.dart';

/// A WebSocket wrapped as a [SyncChannel]. An optional [gate] inspects the very
/// first frame (the server uses it to find out which paired device is calling).
class WsChannel<T> implements SyncChannel {
  WsChannel(this._ws, {Future<T?> Function(Uint8List first)? gate}) : _gate = gate {
    _ws.pingInterval = const Duration(seconds: 25);
    _ws.listen(
      (data) {
        if (data is! List<int>) return;
        final frame = Uint8List.fromList(data);
        _pump = _pump.then((_) async {
          if (_gate != null && !_gated) {
            _gated = true;
            final r = await _gate(frame);
            _gateDone.complete(r);
            if (r == null) {
              await close();
              return;
            }
          }
          if (!_ctrl.isClosed) _ctrl.add(frame);
        });
      },
      onDone: () {
        if (_gate != null && !_gateDone.isCompleted) _gateDone.complete(null);
        _pump.then((_) {
          if (!_ctrl.isClosed) _ctrl.close();
        });
      },
      onError: (Object e) {
        if (_gate != null && !_gateDone.isCompleted) _gateDone.complete(null);
        if (!_ctrl.isClosed) _ctrl.addError(e);
      },
    );
  }

  final WebSocket _ws;
  final Future<T?> Function(Uint8List first)? _gate;
  bool _gated = false;
  final _gateDone = Completer<T?>();
  Future<void> _pump = Future.value();

  // Single-subscription: frames wait here until the session starts listening.
  final _ctrl = StreamController<Uint8List>();

  /// What the gate returned for the first frame (null = rejected / never arrived).
  Future<T?> get gateResult => _gateDone.future;

  @override
  Stream<Uint8List> get incoming => _ctrl.stream;

  @override
  void send(Uint8List data) {
    if (_ws.readyState == WebSocket.open) _ws.add(data);
  }

  @override
  Future<void> close() async {
    try {
      await _ws.close();
    } catch (_) {}
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

const discoveryPort = 47321;
const defaultSyncPort = 47320;

/// The desktop side: listens for phones and answers "where are you?" broadcasts.
class SyncServer {
  SyncServer({required this.deviceId, required this.onSocket, this.onPairSocket});

  final String deviceId;
  final void Function(WebSocket ws, InternetAddress from) onSocket;

  /// Called for a phone that is pairing with a PIN (path /pair).
  final void Function(WebSocket ws, InternetAddress from)? onPairSocket;

  /// Extra names this computer answers to when a phone broadcasts "where are you?"
  /// (e.g. the one-time token of a phone's QR code, or "PIN" while a PIN is shown).
  final Set<String> answerIds = {};
  HttpServer? _http;
  RawDatagramSocket? _udp;

  bool get running => _http != null;
  int get port => _http?.port ?? 0;

  Future<void> start() async {
    if (_http != null) return;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, defaultSyncPort);
    } on SocketException {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _http!.listen((req) async {
      if (req.uri.path == '/sync' && WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        onSocket(ws, req.connectionInfo?.remoteAddress ?? InternetAddress.loopbackIPv4);
      } else if (req.uri.path == '/pair' && onPairSocket != null && WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        onPairSocket!(ws, req.connectionInfo?.remoteAddress ?? InternetAddress.loopbackIPv4);
      } else {
        req.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
    try {
      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
      udp.broadcastEnabled = true;
      udp.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = udp.receive();
        if (d == null) return;
        final msg = utf8.decode(d.data, allowMalformed: true);
        if (msg == 'MYDAY?$deviceId' || (msg.startsWith('MYDAY?') && answerIds.contains(msg.substring(6)))) {
          udp.send(utf8.encode('MYDAY!$port'), d.address, d.port);
        }
      });
      _udp = udp;
    } catch (_) {
      // Discovery is a convenience; pairing by QR still works without it.
    }
  }

  Future<void> stop() async {
    _udp?.close();
    _udp = null;
    await _http?.close(force: true);
    _http = null;
  }
}

/// Opens the short-lived pairing socket (PIN pairing) to the desktop.
Future<WebSocket> connectPairSocket(String host, int port, {Duration timeout = const Duration(seconds: 4)}) =>
    WebSocket.connect('ws://$host:$port/pair').timeout(timeout);

/// Opens a WebSocket to the desktop.
Future<WebSocket> connectSocket(String host, int port, {Duration timeout = const Duration(seconds: 3)}) =>
    WebSocket.connect('ws://$host:$port/sync').timeout(timeout);

/// Looks for the desktop on the local network (UDP broadcast). Returns host and port.
/// Never throws: on some phones broadcasting is blocked, then the saved address is used instead.
Future<(String, int)?> discoverDesktop(String desktopId, {Duration timeout = const Duration(milliseconds: 2500)}) async {
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final result = Completer<(String, int)?>();
    socket.listen(
      (e) {
        if (e != RawSocketEvent.read) return;
        final d = socket!.receive();
        if (d == null) return;
        final msg = utf8.decode(d.data, allowMalformed: true);
        if (msg.startsWith('MYDAY!') && !result.isCompleted) {
          result.complete((d.address.address, int.tryParse(msg.substring(6)) ?? defaultSyncPort));
        }
      },
      onError: (Object _) {}, // a blocked broadcast is reported here; just ignore it
      cancelOnError: false,
    );
    final payload = utf8.encode('MYDAY?$desktopId');
    final targets = <String>{};
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        final p = a.address.split('.');
        if (p.length == 4 && !a.isLoopback) targets.add('${p[0]}.${p[1]}.${p[2]}.255');
      }
    }
    if (targets.isEmpty) targets.add('255.255.255.255');
    for (final t in targets) {
      try {
        socket.send(payload, InternetAddress(t), discoveryPort);
      } catch (_) {}
    }
    return await result.future.timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    socket?.close();
  }
}

/// This computer's private Wi-Fi/LAN addresses (what the phone should try first).
Future<List<String>> localAddresses() async {
  final out = <String>[];
  try {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        final s = a.address;
        final p = s.split('.').map(int.tryParse).toList();
        if (p.length != 4 || p.contains(null)) continue;
        final priv = p[0] == 10 ||
            (p[0] == 192 && p[1] == 168) ||
            (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31);
        if (priv && !s.startsWith('169.254')) out.add(s);
      }
    }
  } catch (_) {}
  out.sort((a, b) => (b.startsWith('192.168') ? 1 : 0).compareTo(a.startsWith('192.168') ? 1 : 0));
  return out;
}
