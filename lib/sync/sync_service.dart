import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../services/settings_service.dart';
import 'background_sync.dart';
import 'sync_cipher.dart';
import 'sync_engine.dart';
import 'sync_log.dart';
import 'sync_net.dart';
import 'sync_pair.dart';
import 'sync_session.dart';

enum SyncStatus { disabled, notPaired, waiting, connecting, connected, syncing, offline }

/// Another device we are paired with.
class PeerRecord {
  PeerRecord({
    required this.id,
    required this.name,
    required this.key,
    this.hosts = const [],
    this.port = defaultSyncPort,
    this.lastSync = 0,
    this.lastHost,
  });

  String id;
  String name;
  String key;
  List<String> hosts;
  int port;
  int lastSync; // ms since epoch
  String? lastHost;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'key': key,
        'hosts': hosts,
        'port': port,
        'lastSync': lastSync,
        'lastHost': lastHost,
      };

  factory PeerRecord.fromJson(Map<String, dynamic> j) => PeerRecord(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'device',
        key: j['key'] as String,
        hosts: [for (final h in (j['hosts'] as List? ?? const [])) '$h'],
        port: (j['port'] as int?) ?? defaultSyncPort,
        lastSync: (j['lastSync'] as int?) ?? 0,
        lastHost: j['lastHost'] as String?,
      );
}

/// What the computer shows while it waits for a phone: a QR code and a 6-digit PIN.
class PairingOffer {
  PairingOffer({required this.payload, required this.pin, required this.addresses, required this.port});
  final String payload;
  final String pin;
  final List<String> addresses;
  final int port;
}

class SyncNotice {
  SyncNotice(this.text) : at = DateTime.now();
  final String text;
  final DateTime at;
}

class _Match {
  _Match(this.cipher, this.peerId, this.key);
  final SyncCipher cipher;
  final String? peerId; // null while the key is the one-time pairing key
  final String key;
}

/// Keeps this device in sync with the paired one.
///
/// The desktop is the hub: it listens on the local network. The phone connects
/// only while the app is open (so it costs no battery in the background),
/// and catches up automatically every time the app is opened.
class SyncService extends ChangeNotifier with WidgetsBindingObserver implements SyncStateStore {
  SyncService({required this.store, required this.settings, bool? hub})
      : isHub = hub ?? (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  final DataStore store;
  final SettingsService settings;
  final bool isHub;

  late SharedPreferences _p;
  late SyncEngine engine;
  late String deviceId;
  late String deviceName;

  List<PeerRecord> peers = [];
  final Map<String, SyncSession> _sessions = {};
  SyncServer? _server;

  // pairing (hub)
  String? _pin;
  int _pinFails = 0;
  String? _pendingKey;
  DateTime? _pendingUntil;
  Timer? _pendingTimer;

  // phone pairing by showing its own QR (the laptop scans it)
  String? _phoneToken;

  // phone connection handling
  bool _connecting = false;
  bool _foreground = true;
  Timer? _retryTimer;
  Timer? _backgroundTimer;
  DateTime? _connectedAt;
  int _attempt = 0;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<void>? _changeSub;
  Timer? _debounce;
  Completer<void>? _syncWaiter;
  bool _syncing = false;
  int _bgApplied = 0;

  String? lastError;
  final List<VaultFile> pendingFiles = [];
  final notice = ValueNotifier<SyncNotice?>(null);

  /// Set when a phone has just been paired (the pairing dialog listens to this).
  final justPaired = ValueNotifier<String?>(null);

  /// Called after changes from the other device were saved (reschedule reminders etc.).
  Future<void> Function()? onDataApplied;

  bool get enabled => _p.getBool('sync.enabled') ?? true;
  bool get backgroundCheck => _p.getBool('sync.bg') ?? false;
  bool get notifyOnChanges => _p.getBool('sync.notify') ?? true;
  bool get pairingOpen => _pendingKey != null && (_pendingUntil?.isAfter(DateTime.now()) ?? false);
  DateTime? get pairingExpires => _pendingUntil;
  bool get hasPeers => peers.isNotEmpty;
  bool get connectedNow => _sessions.values.any((s) => s.isReady && !s.isClosed);
  int get port => _server?.port ?? 0;

  DateTime? get lastSync {
    final t = peers.fold<int>(0, (m, e) => e.lastSync > m ? e.lastSync : m);
    return t == 0 ? null : DateTime.fromMillisecondsSinceEpoch(t);
  }

  SyncStatus get status {
    if (!enabled) return SyncStatus.disabled;
    if (peers.isEmpty && !pairingOpen) return SyncStatus.notPaired;
    if (_syncing && connectedNow) return SyncStatus.syncing;
    if (connectedNow) return SyncStatus.connected;
    if (_connecting) return SyncStatus.connecting;
    if (!isHub && _offline) return SyncStatus.offline;
    return SyncStatus.waiting;
  }

  bool _offline = false;
  bool _askedLocalNetwork = false;

  /// Android 16+ asks before an app may reach other devices on the Wi-Fi.
  Future<void> _ensureLocalNetworkPermission() async {
    if (!Platform.isAndroid || _askedLocalNetwork) return;
    _askedLocalNetwork = true;
    try {
      await const MethodChannel('myday/perm').invokeMethod('requestLocalNetwork');
    } catch (_) {}
  }

  // ───────────────────────── setup ─────────────────────────

  /// Loads identity and pairing info only (used by the background task too).
  Future<void> initCore() async {
    _p = await SharedPreferences.getInstance();
    deviceId = _p.getString('sync.dev') ?? const Uuid().v4();
    await _p.setString('sync.dev', deviceId);
    deviceName = isHub ? Platform.localHostname : 'My phone';
    engine = SyncEngine(store, settings);
    _loadPeers();
    try {
      await SyncLog.init(await getApplicationSupportDirectory());
    } catch (_) {}
    SyncLog.add('sync init as ${isHub ? 'desktop' : 'phone'}, ${peers.length} paired');
  }

  Future<void> init() async {
    await initCore();

    settings.onSyncedChange = (k, v) => store.put('kv', {'key': k, 'value': v});
    _changeSub = store.localChanges.listen((_) => _scheduleAnnounce());

    if (isHub) {
      if (enabled && peers.isNotEmpty) await _startServer();
    } else {
      WidgetsBinding.instance.addObserver(this);
      _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
      if (enabled && peers.isNotEmpty) unawaited(connect());
      if (backgroundCheck) unawaited(BackgroundSync.setEnabled(true));
    }
  }

  void _loadPeers() {
    final raw = _p.getString('sync.peers');
    if (raw == null) return;
    peers = [
      for (final j in jsonDecode(raw) as List) PeerRecord.fromJson(Map<String, dynamic>.from(j as Map)),
    ];
  }

  Future<void> _savePeers() => _p.setString('sync.peers', jsonEncode(peers.map((e) => e.toJson()).toList()));

  // SyncStateStore
  @override
  Future<int> since(String peerId) async => _p.getInt('sync.since.$peerId') ?? 0;

  @override
  Future<void> setSince(String peerId, int value) => _p.setInt('sync.since.$peerId', value);

  Future<void> setEnabled(bool v) async {
    await _p.setBool('sync.enabled', v);
    if (!v) {
      await _closeAll();
      await _server?.stop();
      _server = null;
    } else if (peers.isNotEmpty) {
      if (isHub) {
        await _startServer();
      } else {
        unawaited(connect(force: true));
      }
    }
    notifyListeners();
  }

  Future<void> setBackgroundCheck(bool v) async {
    await _p.setBool('sync.bg', v);
    await BackgroundSync.setEnabled(v);
    notifyListeners();
  }

  /// One quick connect-sync-disconnect for the background task. Returns how many changes arrived.
  Future<int> backgroundSyncOnce() async {
    if (isHub || peers.isEmpty || !enabled) return 0;
    _bgApplied = 0;
    _foreground = true;
    _syncWaiter = Completer<void>();
    await connect(force: true);
    if (_sessions.isNotEmpty) {
      try {
        await _syncWaiter!.future.timeout(const Duration(seconds: 25));
      } on TimeoutException {
        // fall through: take what arrived
      }
      final end = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(end) && _sessions.values.any((s) => s.activeFileJobs > 0)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    _foreground = false;
    _retryTimer?.cancel();
    final n = _bgApplied;
    await _closeAll();
    _retryTimer?.cancel();
    return n;
  }

  Future<void> setNotifyOnChanges(bool v) async {
    await _p.setBool('sync.notify', v);
    notifyListeners();
  }

  // ───────────────────────── hub (desktop) ─────────────────────────

  Future<void> _startServer() async {
    if (_server?.running ?? false) return;
    _server = SyncServer(deviceId: deviceId, onSocket: _onSocket, onPairSocket: _onPairSocket);
    await _server!.start();
    await engine.seedSettings();
    notifyListeners();
  }

  /// Opens a 10-minute window for a new phone. Shows a QR code and a 6-digit PIN.
  Future<PairingOffer> beginPairing() async {
    await _startServer();
    _pendingKey = SyncCipher.generateKey();
    _pendingUntil = DateTime.now().add(const Duration(minutes: 10));
    _pin = (Random.secure().nextInt(900000) + 100000).toString();
    _pinFails = 0;
    _server!.answerIds.add('PIN');
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(minutes: 10), cancelPairing);
    justPaired.value = null;
    notifyListeners();
    final addrs = await localAddresses();
    return PairingOffer(
      payload: jsonEncode({
        'v': 1,
        'id': deviceId,
        'n': deviceName,
        'h': addrs,
        'p': _server!.port,
        'k': _pendingKey,
      }),
      pin: _pin!,
      addresses: addrs,
      port: _server!.port,
    );
  }

  void cancelPairing() {
    _pendingKey = null;
    _pendingUntil = null;
    _pin = null;
    _server?.answerIds.remove('PIN');
    _pendingTimer?.cancel();
    if (isHub && peers.isEmpty) {
      unawaited(_server?.stop());
      _server = null;
    }
    notifyListeners();
  }

  /// A phone typing the 6-digit PIN connects here.
  void _onPairSocket(WebSocket ws, InternetAddress from) {
    final pin = _pin;
    if (!pairingOpen || pin == null) {
      ws.close();
      return;
    }
    SyncLog.add('PIN pairing attempt from ${from.address}');
    PinPairing.hubSide(
      ws,
      pin: pin,
      hubId: deviceId,
      hubName: deviceName,
      onWrongPin: () {
        _pinFails++;
        SyncLog.add('wrong PIN ($_pinFails of 3)');
        if (_pinFails >= 3) cancelPairing(); // three strikes: the PIN stops working
      },
    ).then((r) {
      if (r == null) return;
      SyncLog.add('PIN pairing succeeded with ${r.peerName}');
      peers.removeWhere((p) => p.id == r.peerId);
      peers.add(PeerRecord(id: r.peerId, name: r.peerName, key: r.key));
      unawaited(_savePeers());
      cancelPairing();
      justPaired.value = r.peerName;
      notifyListeners();
    });
  }

  /// The computer scanned a QR code shown on the phone (webcam). The phone will find us and connect.
  Future<String?> pairFromPhoneQr(String data) async {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(data) as Map<String, dynamic>;
      if (j['v'] != 2 || j['k'] == null || j['id'] == null || j['t'] == null) throw const FormatException();
    } catch (_) {
      return 'That QR code is not from MyDay on a phone.';
    }
    await _startServer();
    final token = j['t'] as String;
    peers.removeWhere((p) => p.id == j['id']);
    peers.add(PeerRecord(id: j['id'] as String, name: (j['n'] as String?) ?? 'My phone', key: j['k'] as String));
    await _savePeers();
    _server!.answerIds.add(token);
    Timer(const Duration(minutes: 10), () => _server?.answerIds.remove(token));
    SyncLog.add('scanned a phone QR; waiting for ${j['n']} to connect');
    notifyListeners();
    return null;
  }

  void _onSocket(WebSocket ws, InternetAddress from) {
    SyncLog.add('incoming connection from ${from.address}');
    final candidates = <_Match>[
      for (final p in peers) _Match(SyncCipher.fromBase64(p.key), p.id, p.key),
      if (pairingOpen) _Match(SyncCipher.fromBase64(_pendingKey!), null, _pendingKey!),
    ];
    final ch = WsChannel<_Match>(ws, gate: (first) async {
      for (final c in candidates) {
        if (await c.cipher.decrypt(first) != null) return c;
      }
      return null;
    });
    ch.gateResult.timeout(const Duration(seconds: 8), onTimeout: () => null).then((m) {
      if (m == null) {
        SyncLog.add('dropped connection from ${from.address} (no valid first message, or not a paired device)');
        ch.close();
        return;
      }
      late SyncSession session;
      session = _newSession(ch, m.cipher, (e) => _onEvent(session, e, pendingKey: m.peerId == null ? m.key : null));
      if (m.peerId != null) _replaceSession(m.peerId!, session);
      session.start();
    });
  }

  // ───────────────────────── phone connection ─────────────────────────

  /// Connects to the desktop (phone only). Does nothing in the background unless [force].
  Future<void> connect({bool force = false}) async {
    if (isHub || peers.isEmpty || !enabled || _connecting) return;
    if (connectedNow) return;
    if (!_foreground && !force) return;
    final fresh = _sessions.values.where((x) => !x.isClosed && !x.isReady).toList();
    if (fresh.isNotEmpty && DateTime.now().difference(_connectedAt ?? DateTime(2000)) < const Duration(seconds: 12)) {
      return; // a connection is still introducing itself
    }
    for (final x in fresh) {
      unawaited(x.close('no answer'));
    }
    _connecting = true; // taken before any await so two callers can never connect at once
    _retryTimer?.cancel();
    notifyListeners();
    try {
      // No Wi-Fi pre-check: Android's connectivity report can be wrong right after the app starts,
      // and a real connection attempt to a local address fails fast when there is no Wi-Fi anyway.
      await _ensureLocalNetworkPermission();

      final peer = peers.first;
      WebSocket? ws;
      final tried = <String>{};
      for (final h in [peer.lastHost, ...peer.hosts].whereType<String>()) {
        if (!tried.add(h)) continue;
        try {
          ws = await connectSocket(h, peer.port);
          peer.lastHost = h;
          break;
        } catch (e) {
          SyncLog.add('cannot connect to $h:${peer.port} ($e)');
        }
      }
      if (ws == null) {
        final d = await discoverDesktop(peer.id.startsWith('pending-') ? peer.id.substring(8) : peer.id);
        if (d != null) {
          try {
            ws = await connectSocket(d.$1, d.$2);
            peer.lastHost = d.$1;
            peer.port = d.$2;
            SyncLog.add('found the computer by broadcast at ${d.$1}');
          } catch (_) {}
        }
      }
      if (ws == null) {
        SyncLog.add('computer not found (tried ${tried.join(', ')} and broadcast)');
        throw 'Your computer was not found on this Wi-Fi. Is MyDay open on it?';
      }
      await _savePeers();

      late SyncSession session;
      session = _newSession(WsChannel<void>(ws), SyncCipher.fromBase64(peer.key), (e) => _onEvent(session, e));
      _replaceSession(peer.id, session);
      _connectedAt = DateTime.now();
      session.start();
      SyncLog.add('connected to ${peer.lastHost}:${peer.port}');
      lastError = null;
      _attempt = 0;
    } catch (e) {
      lastError = '$e';
      SyncLog.add('connect failed: $e');
      _scheduleRetry();
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  void _scheduleRetry() {
    if (isHub || !_foreground || !enabled) return;
    const delays = [3, 5, 8, 12, 20]; // seconds; only runs while the app is on screen, so it costs almost nothing
    final waiting = peers.isNotEmpty && peers.first.id.startsWith('pending-');
    final d = waiting ? 2 : delays[_attempt.clamp(0, delays.length - 1)];
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: d), () => connect());
  }

  Future<void> _onConnectivity(List<ConnectivityResult> res) async {
    SyncLog.add('network changed: ${res.map((r) => r.name).join(', ')}');
    final bad = res.every((r) => r == ConnectivityResult.none || r == ConnectivityResult.mobile);
    _offline = bad;
    if (bad) {
      await _closeAll();
    } else if (_foreground) {
      _attempt = 0;
      unawaited(connect());
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isHub) return;
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _backgroundTimer?.cancel();
      _attempt = 0;
      unawaited(_resumeRefresh());
    } else {
      // Drop the connection shortly after the app leaves the screen: no battery use in the background.
      _backgroundTimer?.cancel();
      _backgroundTimer = Timer(const Duration(seconds: 20), () {
        SyncLog.add('app in background, disconnecting');
        _foreground = false;
        _retryTimer?.cancel();
        unawaited(_closeAll());
      });
    }
  }

  Future<void> _resumeRefresh() async {
    SyncLog.add('app resumed');
    await _p.reload(); // the background task may have changed settings/progress
    await store.reload(); // and data
    // A connection that looks open may have died while the app was in the background.
    for (final s in _sessions.values.toList()) {
      if (s.isReady && !await s.isAlive()) {
        SyncLog.add('connection was dead, reconnecting');
        await s.close('stale after background');
      }
    }
    await connect();
    for (final s in _sessions.values) {
      if (s.isReady) {
        s.announceChanged();
        unawaited(s.pull());
      }
    }
  }

  /// Phone: scan result from the desktop's QR code. Returns an error message or null.
  Future<String?> pairFromQr(String data) async {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(data) as Map<String, dynamic>;
      if (j['v'] != 1 || j['k'] == null || j['id'] == null) throw const FormatException();
    } catch (_) {
      return 'That QR code is not from MyDay.';
    }
    await _closeAll();
    peers = [
      PeerRecord(
        id: j['id'] as String,
        name: (j['n'] as String?) ?? 'My computer',
        key: j['k'] as String,
        hosts: [for (final h in (j['h'] as List? ?? const [])) '$h'],
        port: (j['p'] as int?) ?? defaultSyncPort,
      ),
    ];
    await _p.remove('sync.since.${peers.first.id}');
    await _p.setBool('sync.enabled', true);
    await _savePeers();
    notifyListeners();

    _syncWaiter = Completer<void>();
    unawaited(connect(force: true));
    try {
      await _syncWaiter!.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return lastError ?? 'Could not connect. Make sure both devices are on the same Wi-Fi.';
    }
    return null;
  }

  /// Phone: pair by typing the 6-digit PIN shown on the computer. Returns an error message or null.
  Future<String?> pairWithPin(String pin, {String? host}) async {
    await _closeAll();
    SyncLog.add('pairing by PIN${host == null ? ' (looking for the computer)' : ' at $host'}');
    String? h = host;
    var port = defaultSyncPort;
    if (h == null || h.isEmpty) {
      final d = await discoverDesktop('PIN', timeout: const Duration(seconds: 4));
      if (d == null) {
        return 'Could not find your computer. Open "Pair a new phone" on it first, and make sure both are on the same Wi-Fi.';
      }
      h = d.$1;
      port = d.$2;
    }
    await _ensureLocalNetworkPermission();
    WebSocket ws;
    try {
      ws = await connectPairSocket(h, port);
    } catch (e) {
      return 'Could not reach your computer at $h.';
    }
    final r = await PinPairing.clientSide(ws, pin: pin.trim(), myId: deviceId, myName: deviceName);
    if (r == null) return 'That PIN was not accepted. Check the numbers on your computer and try again.';
    peers = [PeerRecord(id: r.peerId, name: r.peerName, key: r.key, hosts: [h], port: port, lastHost: h)];
    await _p.remove('sync.since.${r.peerId}');
    await _p.setBool('sync.enabled', true);
    await _savePeers();
    notifyListeners();
    return _connectAndWaitFirstSync();
  }

  Future<String?> _connectAndWaitFirstSync() async {
    _syncWaiter = Completer<void>();
    unawaited(connect(force: true));
    try {
      await _syncWaiter!.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return lastError ?? 'Paired, but could not connect yet. Open MyDay on both devices on the same Wi-Fi.';
    }
    return null;
  }

  /// Phone: show a QR code that the computer's camera scans. Returns the QR text.
  Future<String> beginPhonePairing() async {
    await _closeAll();
    final key = SyncCipher.generateKey();
    final rnd = Random.secure();
    final token = List.generate(10, (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[rnd.nextInt(31)]).join();
    _phoneToken = token;
    peers = [PeerRecord(id: 'pending-$token', name: 'My computer', key: key)];
    await _savePeers();
    await _p.setBool('sync.enabled', true);
    justPaired.value = null;
    _attempt = 0;
    SyncLog.add('showing a QR for the computer to scan; searching for it');
    unawaited(connect(force: true));
    notifyListeners();
    return jsonEncode({'v': 2, 'id': deviceId, 'n': deviceName, 'k': key, 't': token});
  }

  /// Phone: the QR dialog was closed. Forget the half-finished pairing.
  Future<void> cancelPhonePairing() async {
    if (_phoneToken == null) return;
    _phoneToken = null;
    if (peers.isNotEmpty && peers.first.id.startsWith('pending-')) {
      await _closeAll();
      peers.clear();
      await _savePeers();
    }
    notifyListeners();
  }

  Future<void> unpair(String peerId) async {
    await _sessions.remove(peerId)?.close();
    peers.removeWhere((p) => p.id == peerId);
    await _p.remove('sync.since.$peerId');
    await _savePeers();
    if (isHub && peers.isEmpty && !pairingOpen) {
      await _server?.stop();
      _server = null;
    }
    notifyListeners();
  }

  // ───────────────────────── sessions ─────────────────────────

  SyncSession _newSession(SyncChannel ch, SyncCipher cipher, void Function(SyncEvent) onEvent) => SyncSession(
        channel: ch,
        cipher: cipher,
        engine: engine,
        state: this,
        deviceId: deviceId,
        deviceName: deviceName,
        onEvent: onEvent,
        isFresh: () => !settings.setupDone,
        onPeerFresh: engine.seedIdentity,
      );

  void _replaceSession(String peerId, SyncSession s) {
    final old = _sessions[peerId];
    _sessions[peerId] = s;
    if (old != null && old != s) unawaited(old.close());
  }

  Future<void> _closeAll() async {
    final all = _sessions.values.toList();
    _sessions.clear();
    for (final s in all) {
      await s.close();
    }
    _syncing = false;
    notifyListeners();
  }

  void _onEvent(SyncSession s, SyncEvent e, {String? pendingKey}) {
    switch (e) {
      case PeerReady():
        if (!isHub && peers.isNotEmpty && peers.first.id.startsWith('pending-')) {
          // the computer scanned our QR code and answered: now we know who it is
          final old = peers.first.id;
          _sessions.remove(old);
          peers.first
            ..id = e.id
            ..name = e.name;
          unawaited(_savePeers());
          _phoneToken = null;
          justPaired.value = e.name;
        }
        _replaceSession(e.id, s);
        if (pendingKey != null && pairingOpen) _registerPeer(e, pendingKey);
        final p = peers.where((x) => x.id == e.id).firstOrNull;
        if (isHub && p != null && p.lastSync == 0) justPaired.value = e.name;
        if (p != null && p.name != e.name) {
          p.name = e.name;
          unawaited(_savePeers());
        }
        _syncing = true;
        notifyListeners();
      case SyncedEvent():
        SyncLog.add('sync complete: ${e.applied} changes from ${e.peerName}');
        _syncing = false;
        final p = peers.where((x) => x.id == s.peerId).firstOrNull;
        if (p != null) {
          p.lastSync = DateTime.now().millisecondsSinceEpoch;
          unawaited(_savePeers());
        }
        _bgApplied += e.applied;
        if (e.applied > 0) {
          for (final other in _sessions.values) {
            if (other != s) other.announceChanged();
          }
          if (notifyOnChanges) notice.value = SyncNotice('Synced ${e.applied} change${e.applied == 1 ? '' : 's'} from ${e.peerName}');
          unawaited(onDataApplied?.call());
        }
        if (_syncWaiter != null && !_syncWaiter!.isCompleted) _syncWaiter!.complete();
        notifyListeners();
      case FilesNeedApproval():
        final declined = (_p.getStringList('sync.declined') ?? const []).toSet();
        for (final f in e.files) {
          if (declined.contains(f.id) || pendingFiles.any((x) => x.id == f.id)) continue;
          pendingFiles.add(f);
        }
        notifyListeners();
      case FileReceived():
        pendingFiles.removeWhere((f) => f.id == e.file.id);
        store.refresh();
        notifyListeners();
      case SessionClosed():
        if (e.error != null) lastError = '${e.error}';
        SyncLog.add('session closed event${e.error == null ? '' : ' (${e.error})'}');
        _sessions.removeWhere((_, v) => v == s);
        _syncing = false;
        if (!isHub) _scheduleRetry();
        notifyListeners();
    }
  }

  void _registerPeer(PeerReady e, String key) {
    peers.removeWhere((p) => p.id == e.id);
    peers.add(PeerRecord(id: e.id, name: e.name, key: key));
    _pendingKey = null;
    _pendingUntil = null;
    _pendingTimer?.cancel();
    unawaited(_savePeers());
    justPaired.value = e.name;
  }

  // ───────────────────────── actions ─────────────────────────

  void _scheduleAnnounce() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), () {
      SyncLog.add('local change, announcing to ${_sessions.length} session(s)');
      for (final s in _sessions.values) {
        s.announceChanged();
      }
    });
  }

  /// The manual "Sync now" button. Returns a message when it could not sync.
  Future<String?> syncNow() async {
    if (!enabled) return 'Sync is turned off.';
    if (peers.isEmpty) return 'Pair a device first.';
    if (!connectedNow) {
      if (isHub) return 'No phone is connected. Open MyDay on your phone while on the same Wi-Fi.';
      _syncWaiter = Completer<void>();
      _attempt = 0;
      await connect(force: true);
      if (!connectedNow && _sessions.isEmpty) return lastError ?? 'Could not reach your computer.';
      try {
        await _syncWaiter!.future.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        return 'Timed out waiting for your computer.';
      }
      return null;
    }
    _syncing = true;
    notifyListeners();
    _syncWaiter = Completer<void>();
    for (final s in _sessions.values) {
      s.announceChanged();
      unawaited(s.pull());
    }
    try {
      await _syncWaiter!.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      _syncing = false;
      notifyListeners();
      return 'Timed out. The other device may be busy.';
    }
    return null;
  }

  /// Download files the user approved (or tapped) that were too big to copy automatically.
  bool downloadFiles(List<String> ids) {
    final s = _sessions.values.where((x) => x.isReady).firstOrNull;
    if (s == null) return false;
    for (final id in ids) {
      s.requestFile(id);
    }
    pendingFiles.removeWhere((f) => ids.contains(f.id));
    notifyListeners();
    return true;
  }

  Future<void> declineFiles(List<String> ids) async {
    final declined = (_p.getStringList('sync.declined') ?? const []).toSet()..addAll(ids);
    await _p.setStringList('sync.declined', declined.toList());
    pendingFiles.removeWhere((f) => ids.contains(f.id));
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _retryTimer?.cancel();
    _backgroundTimer?.cancel();
    _pendingTimer?.cancel();
    _changeSub?.cancel();
    _connSub?.cancel();
    if (!isHub) WidgetsBinding.instance.removeObserver(this);
    unawaited(_closeAll());
    unawaited(_server?.stop());
    super.dispose();
  }
}
