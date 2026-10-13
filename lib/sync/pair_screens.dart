import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/settings_service.dart';
import '../widgets/fx.dart';
import 'qr_decode.dart';
import 'sync_service.dart';

bool get hasWebcamScanner => Platform.isWindows;

/// QR code + 6-digit PIN that the computer shows while it waits for a phone.
class LaptopPairPanel extends StatelessWidget {
  const LaptopPairPanel({super.key, required this.offer});
  final PairingOffer offer;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pin = '${offer.pin.substring(0, 3)} ${offer.pin.substring(3)}';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: QrImageView(data: offer.payload, size: 210, backgroundColor: Colors.white),
      ),
      const SizedBox(height: 14),
      Text('or type this PIN on your phone', style: tt.bodySmall),
      const SizedBox(height: 4),
      Text(pin, style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 4, color: cs.primary)),
      if (offer.addresses.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('This computer: ${offer.addresses.first}', style: tt.bodySmall),
        ),
      const SizedBox(height: 4),
      Text('Valid for 10 minutes · both devices on the same Wi-Fi', style: tt.bodySmall),
    ]);
  }
}

/// The laptop's own camera reads the QR code shown on the phone.
class WebcamScanScreen extends StatefulWidget {
  const WebcamScanScreen({super.key});

  @override
  State<WebcamScanScreen> createState() => _WebcamScanScreenState();
}

class _WebcamScanScreenState extends State<WebcamScanScreen> {
  CameraController? _controller;
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'No camera found on this computer.');
        return;
      }
      final c = CameraController(cams.first, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      // Windows cannot stream frames, so take a photo about once a second and look for a QR code in it.
      _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _scan());
    } catch (e) {
      setState(() => _error = 'Could not open the camera. In Windows, go to Settings > Privacy > Camera and allow desktop apps to use it.\n\n($e)');
    }
  }

  Future<void> _scan() async {
    final c = _controller;
    if (_busy || c == null || !c.value.isInitialized) return;
    _busy = true;
    try {
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      try {
        await File(shot.path).delete();
      } catch (_) {}
      final text = await compute(decodeQrFromImage, bytes);
      if (text != null && mounted) {
        _timer?.cancel();
        Navigator.pop(context, text);
      }
    } catch (_) {
      // a dropped frame is fine: try again on the next tick
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text("Scan your phone's QR code")),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(_error!, textAlign: TextAlign.center)))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Stack(fit: StackFit.expand, children: [
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: c.value.previewSize?.height ?? 640,
                              height: c.value.previewSize?.width ?? 480,
                              child: CameraPreview(c),
                            ),
                          ),
                          Center(
                            child: Container(
                              width: 240,
                              height: 240,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white70, width: 3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Text(
                      'On your phone: Settings > Sync > "Show my QR for the computer".\nHold the phone so the QR code is inside the frame.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]),
    );
  }
}

/// First screen on a brand-new computer: bring everything over from the phone.
class PairFromPhoneScreen extends StatefulWidget {
  const PairFromPhoneScreen({super.key});

  @override
  State<PairFromPhoneScreen> createState() => _PairFromPhoneScreenState();
}

class _PairFromPhoneScreenState extends State<PairFromPhoneScreen> {
  late final SyncService _sync = context.read<SyncService>();
  late final SettingsService _settings = context.read<SettingsService>();
  PairingOffer? _offer;
  String? _status;
  String? _connectedTo;

  @override
  void initState() {
    super.initState();
    _sync.justPaired.addListener(_onPaired);
    _settings.addListener(_onSettings);
    _sync.beginPairing().then((o) {
      if (mounted) setState(() => _offer = o);
    });
  }

  @override
  void dispose() {
    _sync.justPaired.removeListener(_onPaired);
    _settings.removeListener(_onSettings);
    _sync.cancelPairing();
    super.dispose();
  }

  void _onPaired() {
    final n = _sync.justPaired.value;
    if (n != null && mounted) setState(() => _connectedTo = n);
  }

  /// Once the phone's settings (including the PIN) arrive, this computer counts as set up.
  void _onSettings() {
    if (_settings.setupDone && mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> _useCamera() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const WebcamScanScreen()));
    if (code == null || !mounted) return;
    final err = await _sync.pairFromPhoneQr(code);
    if (mounted) setState(() => _status = err ?? 'Scanned! Waiting for your phone to connect…');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up from my phone')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Glass(
              blur: true,
              radius: 28,
              padding: const EdgeInsets.all(24),
              child: _connectedTo != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 18),
                      Text('Connected to $_connectedTo', style: tt.titleLarge),
                      const SizedBox(height: 6),
                      const Text('Bringing in your data, PIN and settings…', textAlign: TextAlign.center),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('On your phone', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('Open MyDay > Settings > Sync, then scan this QR code or type the PIN.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 18),
                      if (_offer == null)
                        const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())
                      else
                        LaptopPairPanel(offer: _offer!),
                      if (hasWebcamScanner) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.videocam_outlined),
                          label: const Text("Scan my phone's QR with this camera"),
                          onPressed: _useCamera,
                        ),
                      ],
                      if (_status != null)
                        Padding(padding: const EdgeInsets.only(top: 12), child: Text(_status!, textAlign: TextAlign.center)),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone: show a QR code for the computer's camera to read.
class PhoneShowQrScreen extends StatefulWidget {
  const PhoneShowQrScreen({super.key});

  @override
  State<PhoneShowQrScreen> createState() => _PhoneShowQrScreenState();
}

class _PhoneShowQrScreenState extends State<PhoneShowQrScreen> {
  late final SyncService _sync = context.read<SyncService>();
  String? _payload;

  @override
  void initState() {
    super.initState();
    _sync.justPaired.addListener(_onPaired);
    _sync.beginPhonePairing().then((p) {
      if (mounted) setState(() => _payload = p);
    });
  }

  @override
  void dispose() {
    _sync.justPaired.removeListener(_onPaired);
    _sync.cancelPhonePairing();
    super.dispose();
  }

  void _onPaired() {
    final n = _sync.justPaired.value;
    if (n != null && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paired with $n. Syncing…')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Show my QR')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('On your computer open MyDay > Settings > Sync > "Scan phone\'s QR with this computer\'s camera" (or choose "Set up from my phone" on its first screen), then show it this code.',
                textAlign: TextAlign.center),
            const SizedBox(height: 18),
            if (_payload == null)
              const CircularProgressIndicator()
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(data: _payload!, size: 260, backgroundColor: Colors.white),
              ),
            const SizedBox(height: 14),
            Text('Keep this screen open until it says paired.', style: tt.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// Phone: type the PIN shown on the computer. Returns an error message, or null when paired.
Future<String?> askAndPairWithPin(BuildContext context) async {
  final pin = TextEditingController();
  final host = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Type the PIN'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Shown on your computer under "Pair a new phone".'),
        const SizedBox(height: 12),
        TextField(
          controller: pin,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(fontSize: 26, letterSpacing: 6),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(counterText: '', hintText: '000000'),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: host,
          decoration: const InputDecoration(labelText: 'Computer address (only if not found automatically)', isDense: true),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pair')),
      ],
    ),
  );
  if (go != true || !context.mounted) return 'cancelled';
  if (pin.text.trim().length != 6) return 'The PIN has 6 digits.';
  return context.read<SyncService>().pairWithPin(pin.text, host: host.text.trim());
}
