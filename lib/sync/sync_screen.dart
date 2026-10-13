import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../screens/files_screen.dart' show fmtSize;
import '../widgets/fx.dart';
import 'pair_screens.dart';
import 'sync_log.dart';
import 'sync_service.dart';

String agoText(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 20) return 'just now';
  if (d.inMinutes < 1) return '${d.inSeconds} seconds ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// App-bar button: tap to sync now. Spins while syncing, dot shows connection.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key});

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _tap(SyncService s) async {
    if (!s.hasPeers) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen()));
      return;
    }
    final msg = await s.syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg ?? 'Synced just now')));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncService>();
    final st = s.status;
    final busy = st == SyncStatus.syncing || st == SyncStatus.connecting;
    if (busy && !_spin.isAnimating) _spin.repeat();
    if (!busy && _spin.isAnimating) _spin.stop();
    final dot = switch (st) {
      SyncStatus.connected || SyncStatus.syncing => Colors.greenAccent.shade400,
      SyncStatus.waiting || SyncStatus.connecting => Colors.orangeAccent,
      SyncStatus.offline => Colors.redAccent,
      _ => null,
    };
    return IconButton(
      tooltip: s.hasPeers ? 'Sync now · last synced ${agoText(s.lastSync)}' : 'Set up sync',
      onPressed: () => _tap(s),
      icon: Stack(clipBehavior: Clip.none, children: [
        RotationTransition(
          turns: _spin,
          child: Icon(s.hasPeers ? Icons.sync_rounded : Icons.devices_outlined),
        ),
        if (dot != null && s.hasPeers)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.2)),
            ),
          ),
      ]),
    );
  }
}

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SyncService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final st = s.status;

    final (icon, color, title) = switch (st) {
      SyncStatus.disabled => (Icons.sync_disabled, cs.outline, 'Sync is off'),
      SyncStatus.notPaired => (Icons.devices_outlined, cs.outline, 'Not paired yet'),
      SyncStatus.waiting => (
          Icons.hourglass_top_rounded,
          Colors.orangeAccent,
          s.isHub ? 'Waiting for your phone' : 'Looking for your computer'
        ),
      SyncStatus.connecting => (Icons.sync_rounded, Colors.orangeAccent, 'Connecting…'),
      SyncStatus.connected => (Icons.check_circle_rounded, Colors.greenAccent.shade400, 'Connected'),
      SyncStatus.syncing => (Icons.sync_rounded, Colors.greenAccent.shade400, 'Syncing…'),
      SyncStatus.offline => (Icons.wifi_off_rounded, Colors.redAccent, 'Not on Wi-Fi'),
    };

    final children = <Widget>[
      Glass(
        blur: true,
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text('Last synced ${agoText(s.lastSync)}', style: tt.bodySmall),
              ]),
            ),
          ]),
          if (s.lastError != null && st == SyncStatus.waiting)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(s.lastError!, style: TextStyle(color: cs.error, fontSize: 13)),
            ),
          if (s.hasPeers) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
              onPressed: st == SyncStatus.syncing
                  ? null
                  : () async {
                      final msg = await s.syncNow();
                      if (context.mounted && msg != null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                      }
                    },
            ),
          ],
        ]),
      ),
      if (s.pendingFiles.isNotEmpty) _PendingFilesCard(s),
      if (s.isHub) ..._hubSection(context, s) else ..._phoneSection(context, s),
      Card(
        child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.sync_alt_rounded),
            title: const Text('Sync automatically'),
            subtitle: Text(s.isHub
                ? 'Keeps listening for your phone on the home Wi-Fi'
                : 'Syncs while the app is open on the same Wi-Fi'),
            value: s.enabled,
            onChanged: s.setEnabled,
          ),
          if (Platform.isAndroid)
            SwitchListTile(
              secondary: const Icon(Icons.schedule_rounded),
              title: const Text('Also check every ~30 minutes'),
              subtitle: const Text('In the background, on Wi-Fi only. Uses a little battery; Android picks the exact time.'),
              value: s.backgroundCheck,
              onChanged: s.setBackgroundCheck,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Tell me when changes arrive'),
            subtitle: const Text('A small message like "Synced 3 changes"'),
            value: s.notifyOnChanges,
            onChanged: s.setNotifyOnChanges,
          ),
        ]),
      ),
      Card(
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Connection log'),
          subtitle: const Text('For troubleshooting'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            SelectableText(SyncLog.dump(last: 40), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy log'),
                onPressed: () => Clipboard.setData(ClipboardData(text: SyncLog.dump(last: 200))),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        child: Text(
          'How it works: your devices talk directly over your own Wi-Fi, encrypted. Nothing is sent to the internet. '
          'Files up to 10 MB copy automatically; bigger ones ask first.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: revealAll([for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)]),
          ),
        ),
      ),
    );
  }

  List<Widget> _hubSection(BuildContext context, SyncService s) => [
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.phone_android_rounded),
              title: Text(s.peers.isEmpty ? 'No phone paired' : 'Paired phones'),
              subtitle: s.peers.isEmpty ? const Text('Pair your phone to start syncing') : null,
            ),
            for (final p in s.peers)
              ListTile(
                leading: const Icon(Icons.smartphone_rounded),
                title: Text(p.name),
                subtitle: Text('Last synced ${agoText(p.lastSync == 0 ? null : DateTime.fromMillisecondsSinceEpoch(p.lastSync))}'),
                trailing: IconButton(
                  tooltip: 'Unpair',
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: () => _confirmUnpair(context, s, p),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 10, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Pair a new phone (QR or PIN)'),
                    onPressed: () => showPairDialog(context),
                  ),
                  if (hasWebcamScanner)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text("Scan a phone's QR with this camera"),
                      onPressed: () => scanPhoneWithCamera(context),
                    ),
                ]),
              ),
            ),
          ]),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Windows Firewall'),
            subtitle: const Text(
                'The first time, Windows asks to allow MyDay on the network. Choose "Private networks" and Allow.'),
          ),
        ),
      ];

  List<Widget> _phoneSection(BuildContext context, SyncService s) {
    if (s.peers.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pair with your computer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                  'On your computer open MyDay > Settings > Sync > Pair a new phone (or choose "Set up from my phone" on a new computer). Then pick a way to connect:'),
              const SizedBox(height: 14),
              const _PhonePairButtons(),
            ]),
          ),
        ),
      ];
    }
    final p = s.peers.first;
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.computer_rounded),
          title: Text(p.name),
          subtitle: Text('Paired computer${p.lastHost == null ? '' : ' · ${p.lastHost}'}'),
          trailing: IconButton(
            tooltip: 'Unpair',
            icon: const Icon(Icons.link_off_rounded),
            onPressed: () => _confirmUnpair(context, s, p),
          ),
        ),
      ),
    ];
  }

  Future<void> _confirmUnpair(BuildContext context, SyncService s, PeerRecord p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Unpair ${p.name}?'),
        content: const Text('Your data stays on both devices. They just stop syncing until you pair again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unpair')),
        ],
      ),
    );
    if (ok == true) await s.unpair(p.id);
  }
}

class _PendingFilesCard extends StatelessWidget {
  const _PendingFilesCard(this.s);
  final SyncService s;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Large files waiting', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final f in s.pendingFiles)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text(f.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(fmtSize(f.size)),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 10, children: [
            FilledButton(
                onPressed: () => s.downloadFiles([for (final f in s.pendingFiles) f.id]),
                child: const Text('Download all')),
            TextButton(
                onPressed: () => s.declineFiles([for (final f in s.pendingFiles) f.id]),
                child: const Text('Not now')),
          ]),
        ]),
      ),
    );
  }
}

/// Shows the QR code and the PIN a phone can use to pair (computer).
Future<void> showPairDialog(BuildContext context) async {
  final s = context.read<SyncService>();
  final offer = await s.beginPairing();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PairDialog(offer: offer),
  );
  s.cancelPairing();
}

/// The computer's camera reads the QR code shown on the phone.
Future<void> scanPhoneWithCamera(BuildContext context) async {
  final s = context.read<SyncService>();
  final messenger = ScaffoldMessenger.of(context);
  final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const WebcamScanScreen()));
  if (code == null) return;
  final err = await s.pairFromPhoneQr(code);
  messenger.showSnackBar(SnackBar(
      content: Text(err ?? 'Scanned. Keep the QR screen open on your phone: it connects in a few seconds.')));
}

class _PairDialog extends StatefulWidget {
  const _PairDialog({required this.offer});
  final PairingOffer offer;

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late final SyncService _s = context.read<SyncService>();

  @override
  void initState() {
    super.initState();
    _s.justPaired.addListener(_onPaired);
  }

  @override
  void dispose() {
    _s.justPaired.removeListener(_onPaired);
    super.dispose();
  }

  void _onPaired() {
    final name = _s.justPaired.value;
    if (name != null && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paired with $name. Syncing…')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair a new phone'),
      content: SizedBox(
        width: 330,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('On your phone open MyDay > Settings > Sync, then scan the QR code or type the PIN.',
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            LaptopPairPanel(offer: widget.offer),
          ]),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy code'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.offer.payload));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pairing code copied')));
          },
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}

/// The phone's three ways to pair.
class _PhonePairButtons extends StatelessWidget {
  const _PhonePairButtons();

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    return Wrap(spacing: 10, runSpacing: 8, children: [
      FilledButton.icon(
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan its QR code'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairScanScreen())),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.pin_outlined),
        label: const Text('Type its PIN'),
        onPressed: () async {
          final err = await askAndPairWithPin(context);
          if (err != null && err != 'cancelled') messenger.showSnackBar(SnackBar(content: Text(err)));
        },
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('Show my QR to its camera'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneShowQrScreen())),
      ),
    ]);
  }
}

/// Phone: scan the desktop's QR code (or paste its code) to pair.
class PairScanScreen extends StatefulWidget {
  const PairScanScreen({super.key});

  @override
  State<PairScanScreen> createState() => _PairScanScreenState();
}

class _PairScanScreenState extends State<PairScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pair(String data) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _controller.stop();
    final err = await context.read<SyncService>().pairFromQr(data);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan the QR code')),
      body: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(fit: StackFit.expand, children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                    if (raw != null) _pair(raw);
                  },
                ),
                if (_busy)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text('Pairing and syncing…', style: TextStyle(color: Colors.white)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _code,
                decoration: const InputDecoration(hintText: 'Or paste the pairing code', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy ? null : () => _pair(_code.text.trim()), child: const Text('Pair')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(spacing: 8, children: [
            TextButton.icon(
              icon: const Icon(Icons.pin_outlined, size: 18),
              label: const Text('Type the PIN instead'),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final err = await askAndPairWithPin(context);
                      if (!mounted) return;
                      if (err == null) {
                        Navigator.pop(context, true);
                        return;
                      }
                      setState(() {
                        _busy = false;
                        _error = err == 'cancelled' ? null : err;
                      });
                    },
            ),
            TextButton.icon(
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: const Text('Show my QR to the computer'),
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await Navigator.push<bool>(
                          context, MaterialPageRoute(builder: (_) => const PhoneShowQrScreen()));
                      if (ok == true && mounted) Navigator.pop(context, true);
                    },
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Listens for big files that need a yes/no and shows a dialog (mount once in the app shell).
class SyncListeners extends StatefulWidget {
  const SyncListeners({super.key, required this.child});
  final Widget child;

  @override
  State<SyncListeners> createState() => _SyncListenersState();
}

class _SyncListenersState extends State<SyncListeners> {
  bool _asking = false;
  final _asked = <String>{};
  late final SyncService _s = context.read<SyncService>();

  @override
  void initState() {
    super.initState();
    _s.addListener(_checkFiles);
    _s.notice.addListener(_showNotice);
  }

  @override
  void dispose() {
    _s.removeListener(_checkFiles);
    _s.notice.removeListener(_showNotice);
    super.dispose();
  }

  void _showNotice() {
    final n = _s.notice.value;
    if (n == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(n.text), duration: const Duration(seconds: 3)));
  }

  Future<void> _checkFiles() async {
    if (_asking || !mounted) return;
    final files = _s.pendingFiles.where((f) => !_asked.contains(f.id)).toList();
    if (files.isEmpty) return;
    _asking = true;
    _asked.addAll(files.map((f) => f.id));
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Copy large files?'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('These files are on your other device and are bigger than 10 MB:'),
            const SizedBox(height: 10),
            for (final f in files.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f.name, overflow: TextOverflow.ellipsis)),
                  Text(fmtSize(f.size), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            if (files.length > 6) Text('…and ${files.length - 6} more'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'never'), child: const Text("Don't ask again")),
          TextButton(onPressed: () => Navigator.pop(context, 'later'), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, 'yes'), child: const Text('Copy')),
        ],
      ),
    );
    final ids = [for (final f in files) f.id];
    if (choice == 'yes') {
      _s.downloadFiles(ids);
    } else if (choice == 'never') {
      await _s.declineFiles(ids);
    }
    _asking = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// True on phones/tablets; used to tune the UI.
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
