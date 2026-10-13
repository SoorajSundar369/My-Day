import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/models.dart';
import 'sync_cipher.dart';
import 'sync_log.dart';
import 'sync_engine.dart';

/// A two-way message pipe (a WebSocket in the app, an in-memory pair in tests).
abstract class SyncChannel {
  Stream<Uint8List> get incoming;
  void send(Uint8List data);
  Future<void> close();
}

/// Remembers, per other device, how far we have already pulled from it.
abstract class SyncStateStore {
  Future<int> since(String peerId);
  Future<void> setSince(String peerId, int value);
}

sealed class SyncEvent {}

class PeerReady extends SyncEvent {
  PeerReady(this.id, this.name);
  final String id, name;
}

class SyncedEvent extends SyncEvent {
  SyncedEvent(this.applied, this.peerName);
  final int applied;
  final String peerName;
}

/// Files that arrived as records only and are too big to copy without asking.
class FilesNeedApproval extends SyncEvent {
  FilesNeedApproval(this.files);
  final List<VaultFile> files;
}

class FileReceived extends SyncEvent {
  FileReceived(this.file);
  final VaultFile file;
}

class SessionClosed extends SyncEvent {
  SessionClosed([this.error]);
  final Object? error;
}

class _Incoming {
  _Incoming(this.sink, this.part, this.target, this.file);
  final IOSink sink;
  final File part;
  final File target;
  final VaultFile file;
}

/// One live connection to one other device. Both sides run the same code.
///
/// Messages (JSON, after encryption):
///   hello   – who I am and what time I think it is
///   pull    – "send me everything changed since counter N"
///   delta   – a page of changed rows (last page tells us the new counter)
///   changed – "something changed here, please pull"
///   file_*  – file bytes on request
class SyncSession {
  SyncSession({
    required this.channel,
    required this.cipher,
    required this.engine,
    required this.state,
    required this.deviceId,
    required this.deviceName,
    this.autoFileBytes = 10 * 1024 * 1024,
    this.onEvent,
    this.isFresh,
    this.onPeerFresh,
  });

  final SyncChannel channel;
  final SyncCipher cipher;
  final SyncEngine engine;
  final SyncStateStore state;
  final String deviceId;
  final String deviceName;
  final int autoFileBytes;
  void Function(SyncEvent)? onEvent;

  /// True while this device has not been set up yet (so the other one should share its identity).
  final bool Function()? isFresh;

  /// Called when the other device is brand new and we are not: share PIN and settings with it.
  final Future<void> Function()? onPeerFresh;

  String? peerId;
  bool peerFresh = false;
  String peerName = '';
  int _offset = 0;
  bool _ready = false;
  bool _closed = false;
  bool _pulling = false;
  bool _pullAgain = false;
  int _appliedTotal = 0;

  /// Files we already asked for in this session, and ones the other side does not have.
  final _requested = <String>{};
  final _unavailable = <String>{};
  final _incoming = <String, _Incoming>{};
  final _jobs = <String>{};
  final _pings = <Object?, Completer<void>>{};
  int _pingId = 0;

  /// File downloads started but not finished yet.
  int get activeFileJobs => _jobs.length;

  StreamSubscription<Uint8List>? _sub;
  Future<void> _in = Future.value();
  Future<void> _out = Future.value();

  bool get isReady => _ready;
  bool get isClosed => _closed;

  /// Begins listening and introduces ourselves.
  void start() {
    _sub = channel.incoming.listen(
      (frame) => _in = _in.then((_) => _onFrame(frame)).catchError((Object e) {
        close(e);
      }),
      onDone: () => close(),
      onError: (Object e) => close(e),
    );
    _sendJson({
      't': 'hello',
      'dev': deviceId,
      'name': deviceName,
      'now': DateTime.now().millisecondsSinceEpoch,
      'fresh': isFresh?.call() ?? false,
    });
  }

  /// For a first frame the server already decrypted while identifying us.
  Future<void> injectPlain(Uint8List plain) => _in = _in.then((_) => _onPlain(plain));

  Future<void> close([Object? error]) async {
    if (_closed) return;
    _closed = true;
    SyncLog.add('session with ${peerName.isEmpty ? '?' : peerName} closed${error == null ? '' : ': $error'}');
    for (final i in _incoming.values) {
      try {
        await i.sink.close();
        if (await i.part.exists()) await i.part.delete();
      } catch (_) {}
    }
    _incoming.clear();
    await _sub?.cancel();
    try {
      await channel.close();
    } catch (_) {}
    onEvent?.call(SessionClosed(error));
  }

  // ---- sending ----
  void _sendJson(Map<String, Object?> m) => _sendRaw([0, ...utf8.encode(jsonEncode(m))]);

  void _sendRaw(List<int> plain) {
    _out = _out.then((_) async {
      if (_closed) return;
      channel.send(await cipher.encrypt(plain));
    }).catchError((Object e) {
      close(e);
    });
  }

  /// True if the other device answers within [timeout] (detects a dead connection).
  Future<bool> isAlive({Duration timeout = const Duration(seconds: 3)}) async {
    if (!_ready || _closed) return false;
    final id = ++_pingId;
    final c = Completer<void>();
    _pings[id] = c;
    _sendJson({'t': 'ping', 'id': id});
    try {
      await c.future.timeout(timeout);
      return true;
    } on TimeoutException {
      _pings.remove(id);
      return false;
    }
  }

  /// Tell the other device something changed here so it pulls right away.
  void announceChanged() {
    if (_ready && !_closed) _sendJson({'t': 'changed'});
  }

  /// Ask the other device for everything new.
  Future<void> pull() async {
    if (!_ready || _closed) return;
    if (_pulling) {
      _pullAgain = true;
      return;
    }
    _pulling = true;
    _appliedTotal = 0;
    _sendJson({'t': 'pull', 'since': await state.since(peerId!)});
  }

  void requestFile(String id) {
    if (!_ready || _requested.contains(id) || _unavailable.contains(id)) return;
    _requested.add(id);
    _jobs.add(id);
    _sendJson({'t': 'file_get', 'id': id});
  }

  /// Retries/starts downloads for files we hold records for but not bytes.
  /// Small ones are fetched; big ones are reported for approval.
  void _planFileDownloads() {
    final missing = engine.store.files.where((f) => !engine.store.hasLocalFile(f) && !_unavailable.contains(f.id));
    final ask = <VaultFile>[];
    for (final f in missing) {
      if (f.size <= autoFileBytes) {
        requestFile(f.id);
      } else if (!_requested.contains(f.id)) {
        ask.add(f);
      }
    }
    if (ask.isNotEmpty) onEvent?.call(FilesNeedApproval(ask));
  }

  // ---- receiving ----
  Future<void> _onFrame(Uint8List frame) async {
    final plain = await cipher.decrypt(frame);
    if (plain == null) {
      await close('Message could not be verified');
      return;
    }
    await _onPlain(plain);
  }

  Future<void> _onPlain(Uint8List plain) async {
    if (plain.isEmpty) return;
    if (plain[0] == 1) return _onChunk(plain);
    final m = jsonDecode(utf8.decode(plain.sublist(1))) as Map<String, dynamic>;
    switch (m['t']) {
      case 'hello':
        peerId = m['dev'] as String;
        peerName = (m['name'] as String?) ?? 'device';
        _offset = (m['now'] as int) - DateTime.now().millisecondsSinceEpoch;
        peerFresh = m['fresh'] == true;
        if (peerFresh && !(isFresh?.call() ?? false)) {
          SyncLog.add('$peerName is brand new: sharing PIN and settings with it');
          await onPeerFresh?.call();
        }
        _ready = true;
        SyncLog.add('hello from $peerName (clock offset ${_offset}ms)');
        onEvent?.call(PeerReady(peerId!, peerName));
        await pull();
      case 'changed':
        SyncLog.add('peer says: changed');
        await pull();
      case 'pull':
        await _servePull(m['since'] as int);
      case 'ping':
        _sendJson({'t': 'pong', 'id': m['id']});
      case 'pong':
        final w = _pings.remove(m['id']);
        if (w != null && !w.isCompleted) w.complete();
      case 'delta':
        await _onDelta(m);
      case 'file_get':
        await _serveFile(m['id'] as String);
      case 'file_missing':
        _unavailable.add(m['id'] as String);
        _jobs.remove(m['id'] as String);
      case 'file_start':
        await _onFileStart(m);
      case 'file_end':
        await _onFileEnd(m['id'] as String);
    }
  }

  Future<void> _servePull(int since) async {
    final upto = engine.store.currentSeq;
    if (since > upto) since = 0; // the other side is ahead of us: our data was reset, resend everything
    final rows = await engine.rowsSince(since, peerId!);
    SyncLog.add('peer pulled since $since: sending ${rows.values.fold<int>(0, (a, b) => a + b.length)} changes');
    final flat = <(String, Map<String, Object?>)>[
      for (final e in rows.entries)
        for (final r in e.value) (e.key, r),
    ];
    if (flat.isEmpty) {
      _sendJson({'t': 'delta', 'upto': upto, 'last': true, 'tables': <String, Object?>{}});
      return;
    }
    const page = 250;
    for (var i = 0; i < flat.length; i += page) {
      final chunk = flat.sublist(i, i + page > flat.length ? flat.length : i + page);
      final tables = <String, List<Map<String, Object?>>>{};
      for (final (t, r) in chunk) {
        (tables[t] ??= []).add(r);
      }
      _sendJson({'t': 'delta', 'upto': upto, 'last': i + page >= flat.length, 'tables': tables});
    }
  }

  Future<void> _onDelta(Map<String, dynamic> m) async {
    final tables = <String, List<Map<String, Object?>>>{
      for (final e in (m['tables'] as Map).entries)
        e.key as String: [for (final r in e.value as List) Map<String, Object?>.from(r as Map)],
    };
    final res = await engine.applyRows(tables, peerId: peerId!, clockOffset: _offset);
    _appliedTotal += res.applied;
    SyncLog.add('received ${res.applied} changes (${res.tables.join(', ')})${m['last'] == true ? ' [last page]' : ''}');
    if (m['last'] != true) return;

    await state.setSince(peerId!, m['upto'] as int);
    _pulling = false;
    if (_appliedTotal > 0) await engine.store.reload();
    onEvent?.call(SyncedEvent(_appliedTotal, peerName));
    _planFileDownloads();
    if (_pullAgain) {
      _pullAgain = false;
      await pull();
    }
  }

  // ---- files ----
  Future<void> _serveFile(String id) async {
    final store = engine.store;
    final f = store.files.where((e) => e.id == id).firstOrNull;
    final file = f == null ? null : File(f.path);
    if (f == null || file == null || !await file.exists()) {
      _sendJson({'t': 'file_missing', 'id': id});
      return;
    }
    _sendJson({'t': 'file_start', 'id': id, 'size': await file.length()});
    final idBytes = utf8.encode(id);
    await for (final chunk in file.openRead()) {
      for (var i = 0; i < chunk.length; i += 128 * 1024) {
        final end = i + 128 * 1024 > chunk.length ? chunk.length : i + 128 * 1024;
        _sendRaw([1, idBytes.length, ...idBytes, ...chunk.sublist(i, end)]);
      }
      await Future<void>.delayed(Duration.zero);
    }
    _sendJson({'t': 'file_end', 'id': id});
  }

  Future<void> _onFileStart(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final f = engine.store.files.where((e) => e.id == id).firstOrNull;
    if (f == null) return;
    final target = File(f.path);
    final part = File('${f.path}.part');
    await part.parent.create(recursive: true);
    _incoming[id] = _Incoming(part.openWrite(), part, target, f);
  }

  Future<void> _onChunk(Uint8List plain) async {
    final idLen = plain[1];
    final id = utf8.decode(plain.sublist(2, 2 + idLen));
    _incoming[id]?.sink.add(plain.sublist(2 + idLen));
  }

  Future<void> _onFileEnd(String id) async {
    final inc = _incoming.remove(id);
    _jobs.remove(id);
    if (inc == null) return;
    await inc.sink.flush();
    await inc.sink.close();
    if (await inc.target.exists()) await inc.target.delete();
    await inc.part.rename(inc.target.path);
    onEvent?.call(FileReceived(inc.file));
  }
}
