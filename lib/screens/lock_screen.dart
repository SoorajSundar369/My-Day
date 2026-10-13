import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/biometric_service.dart';
import '../services/lock_controller.dart';
import '../services/settings_service.dart';
import '../widgets/fx.dart';
import '../widgets/pin_pad.dart';

enum _Mode { pin, question, reset }

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  static const maxAttempts = 5;
  final _pinKey = GlobalKey<PinPadState>();
  final _answer = TextEditingController();
  late _Mode _mode;
  String? _error;
  bool _showHint = false;
  String? _firstNewPin;
  bool _bioBusy = false;
  Timer? _awayTimer;
  bool _awayLong = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBio());
    // Attempts persist across restarts, so a locked-out state stays locked out.
    final failed = context.read<SettingsService>().failedAttempts;
    _mode = failed >= maxAttempts ? _Mode.question : _Mode.pin;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _awayTimer?.cancel();
    _answer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Closing the fingerprint prompt also makes the app "resume": that must NOT open it again,
    // or the PIN could never be typed. Only offer it again after the app was really away for a few seconds.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _awayTimer?.cancel();
      _awayTimer = Timer(const Duration(seconds: 4), () => _awayLong = true);
    } else if (state == AppLifecycleState.resumed) {
      _awayTimer?.cancel();
      if (_awayLong) {
        _awayLong = false;
        _tryBio();
      }
    }
  }

  /// Fingerprint instead of the PIN (the PIN pad stays available as the backup).
  Future<void> _tryBio() async {
    final s = context.read<SettingsService>();
    if (_bioBusy || !s.bioApp || _mode != _Mode.pin || !mounted) return;
    _bioBusy = true;
    final ok = await context.read<BiometricService>().authenticate('Unlock ${s.appName}');
    _bioBusy = false;
    if (ok && mounted) context.read<LockController>().unlock();
  }

  void _onPin(String pin) {
    final s = context.read<SettingsService>();
    if (s.verifyPin(pin)) {
      context.read<LockController>().unlock();
      return;
    }
    final left = maxAttempts - s.failedAttempts;
    setState(() {
      if (left <= 0) {
        _mode = _Mode.question;
        _error = null;
      } else {
        _error = 'Wrong PIN. $left attempt${left == 1 ? '' : 's'} left.';
      }
    });
    _pinKey.currentState?.shake();
  }

  void _checkAnswer() {
    final s = context.read<SettingsService>();
    if (s.verifyAnswer(_answer.text)) {
      setState(() {
        _mode = _Mode.reset;
        _error = null;
      });
    } else {
      setState(() => _error = 'That answer is not right.');
    }
  }

  Future<void> _onNewPin(String pin) async {
    if (_firstNewPin == null) {
      setState(() => _firstNewPin = pin);
      _pinKey.currentState?.clear();
    } else if (_firstNewPin == pin) {
      final s = context.read<SettingsService>();
      final lock = context.read<LockController>();
      await s.setPin(pin);
      lock.unlock();
    } else {
      setState(() {
        _firstNewPin = null;
        _error = "PINs didn't match. Try again.";
      });
      _pinKey.currentState?.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;
    final body = switch (_mode) {
      _Mode.pin => Column(children: [
          const Text('Enter your PIN'),
          const SizedBox(height: 16),
          PinPad(key: _pinKey, onComplete: _onPin),
        ]),
      _Mode.question => Column(children: [
          const Text('Too many wrong attempts.\nAnswer your security question to continue.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(s.securityQuestion, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Your answer'),
            onSubmitted: (_) => _checkAnswer(),
          ),
          const SizedBox(height: 8),
          if (s.securityHint.isNotEmpty)
            _showHint
                ? Text('Hint: ${s.securityHint}')
                : TextButton.icon(
                    onPressed: () => setState(() => _showHint = true),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Show hint')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _checkAnswer, child: const Text('Continue')),
        ]),
      _Mode.reset => Column(children: [
          Text(_firstNewPin == null ? 'Set a new 4-digit PIN' : 'Confirm your new PIN'),
          const SizedBox(height: 16),
          PinPad(key: _pinKey, onComplete: _onNewPin),
        ]),
    };

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const FloatingIcon(size: 92),
              const SizedBox(height: 18),
              Text(s.appName, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              GradientText(s.greeting(),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 28),
              Glass(blur: true, radius: 28, padding: const EdgeInsets.all(24), child: body),
              if (s.bioApp && _mode == _Mode.pin)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.fingerprint, size: 26),
                    label: const Text('Use fingerprint'),
                    onPressed: _tryBio,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(_error!, style: TextStyle(color: cs.error)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
