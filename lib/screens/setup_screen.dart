import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock_controller.dart';
import '../sync/pair_screens.dart';
import '../sync/sync_screen.dart';
import '../services/settings_service.dart';
import '../widgets/fx.dart';
import '../widgets/pin_pad.dart';

/// First-run wizard: name -> PIN -> security question.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _nick = TextEditingController();
  final _question = TextEditingController();
  final _answer = TextEditingController();
  final _hint = TextEditingController();
  final _pinKey = GlobalKey<PinPadState>();
  String? _firstPin;
  String? _pin;
  String? _error;

  void _onPin(String pin) {
    if (_firstPin == null) {
      setState(() {
        _firstPin = pin;
        _error = null;
      });
      _pinKey.currentState?.clear();
    } else if (_firstPin == pin) {
      setState(() {
        _pin = pin;
        _step = 2;
        _error = null;
      });
    } else {
      setState(() {
        _firstPin = null;
        _error = "PINs didn't match. Start again.";
      });
      _pinKey.currentState?.clear();
    }
  }

  /// Phone: copy name and data from the computer instead of typing it again.
  Future<void> _pairWithComputer() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const PairScanScreen()));
    if (ok != true || !mounted) return;
    final s = context.read<SettingsService>();
    // The computer already shared the PIN and settings: nothing to set up, the app moves on by itself.
    if (s.setupDone) return;
    _name.text = s.name;
    _nick.text = s.nickname;
    setState(() => _step = s.name.isEmpty ? 0 : 1);
  }

  Future<void> _finish() async {
    final s = context.read<SettingsService>();
    final lock = context.read<LockController>();
    await s.saveProfile(name: _name.text.trim(), nickname: _nick.text.trim());
    await s.setPin(_pin!);
    await s.setSecurity(
        question: _question.text.trim(), answer: _answer.text, hint: _hint.text.trim());
    lock.unlock();
    await s.completeSetup();
  }

  @override
  Widget build(BuildContext context) {
    final appName = context.read<SettingsService>().appName;
    final step = switch (_step) {
      0 => _nameStep(),
      1 => _pinStep(),
      _ => _securityStep(),
    };
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const FloatingIcon(size: 92),
              const SizedBox(height: 8),
              Text('Welcome to $appName', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Step ${_step + 1} of 3', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              Glass(
                blur: true,
                radius: 28,
                padding: const EdgeInsets.all(24),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                          position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(a),
                          child: c),
                    ),
                    child: KeyedSubtree(key: ValueKey(_step), child: step),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _nameStep() {
    return Column(children: [
      const Text('Let\'s get to know you.'),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Your name'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _nick,
        decoration: const InputDecoration(labelText: 'Nickname (what the app calls you)'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 20),
      if (Platform.isAndroid) ...[
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Already use MyDay on my computer'),
          onPressed: _pairWithComputer,
        ),
        const SizedBox(height: 12),
      ] else ...[
        OutlinedButton.icon(
          icon: const Icon(Icons.phone_android_rounded),
          label: const Text('Set up from my phone'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairFromPhoneScreen())),
        ),
        const SizedBox(height: 12),
      ],
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () {
                if (_nick.text.trim().isEmpty) _nick.text = _name.text.trim();
                setState(() => _step = 1);
              },
        child: const Text('Next'),
      ),
    ]);
  }

  Widget _pinStep() {
    return Column(children: [
      Text(_firstPin == null ? 'Create a 4-digit PIN' : 'Confirm your PIN'),
      const SizedBox(height: 16),
      PinPad(key: _pinKey, onComplete: _onPin),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
    ]);
  }

  Widget _securityStep() {
    final ready = _question.text.trim().isNotEmpty && _answer.text.trim().isNotEmpty;
    return Column(children: [
      const Text('Security question — used if you forget your PIN.'),
      const SizedBox(height: 16),
      TextField(
        controller: _question,
        decoration: const InputDecoration(labelText: 'Question (e.g. First pet\'s name?)'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _answer,
        decoration: const InputDecoration(labelText: 'Answer'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _hint,
        decoration: const InputDecoration(labelText: 'Hint (optional)'),
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: ready ? _finish : null, child: const Text('Finish')),
    ]);
  }
}
