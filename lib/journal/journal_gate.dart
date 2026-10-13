import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/biometric_service.dart';
import '../services/journal_lock.dart';
import '../services/settings_service.dart';
import '../services/sound_service.dart';
import '../widgets/fx.dart';
import '../widgets/pin_pad.dart';
import 'journal_home.dart';

/// What you see when you tap "Journal": first-time setup, then the book opening,
/// then the PIN (if needed), then your journal.
class JournalGate extends StatefulWidget {
  const JournalGate({super.key});

  @override
  State<JournalGate> createState() => _JournalGateState();
}

enum _Stage { setup, book, home }

class _JournalGateState extends State<JournalGate> with SingleTickerProviderStateMixin {
  late final JournalLock _lock = context.read<JournalLock>();
  late final AnimationController _anim;
  late _Stage _stage;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
    final s = context.read<SettingsService>();
    _stage = s.journalSetupDone ? _Stage.book : _Stage.setup;
    if (_stage == _Stage.book) _openBook();
    _lock.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    _lock.removeListener(_onLockChanged);
    _lock.leave();
    _anim.dispose();
    super.dispose();
  }

  /// The "Lock" button inside the journal (or the app locking) sends you back to the cover.
  void _onLockChanged() {
    if (_stage == _Stage.home && !_lock.isOpen && mounted) {
      setState(() => _stage = _Stage.book);
      _openBook();
    }
  }

  void _openBook() {
    context.read<SoundService>().play(Sfx.journalOpen);
    _anim.forward(from: 0).whenComplete(() {
      // No PIN needed (grace period still running): go straight in.
      if (mounted && _stage == _Stage.book && !_lock.needsPin) {
        _lock.markUnlocked();
        setState(() => _stage = _Stage.home);
      }
    });
  }

  void _unlocked() {
    _lock.markUnlocked();
    if (mounted) setState(() => _stage = _Stage.home);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: switch (_stage) {
        _Stage.setup => JournalSetupFlow(
            key: const ValueKey('setup'),
            onDone: () => setState(() {
              _stage = _Stage.book;
              _openBook();
            }),
          ),
        _Stage.book => _BookOpening(key: const ValueKey('book'), anim: _anim, onUnlocked: _unlocked),
        _Stage.home => const JournalHome(key: ValueKey('home')),
      },
    );
  }
}

// ───────────────────────── first-time setup ─────────────────────────

/// "Same PIN as the app, or a separate journal PIN (4 or 6 digits)?"
class JournalSetupFlow extends StatefulWidget {
  const JournalSetupFlow({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<JournalSetupFlow> createState() => _JournalSetupFlowState();
}

class _JournalSetupFlowState extends State<JournalSetupFlow> {
  int _step = 0; // 0 choose, 1 length, 2 create, 3 confirm
  int _length = 4;
  String? _first;
  String? _error;
  // One key per step: both steps can be on screen together while the page animates.
  final _createKey = GlobalKey<PinPadState>();
  final _confirmKey = GlobalKey<PinPadState>();

  Future<void> _useAppPin() async {
    await context.read<SettingsService>().completeJournalSetup(mode: 'app');
    widget.onDone();
  }

  Future<void> _onPin(String pin) async {
    if (_step == 2) {
      setState(() {
        _first = pin;
        _step = 3;
        _error = null;
      });
    } else if (_first == pin) {
      await context.read<SettingsService>().completeJournalSetup(mode: 'own', length: _length, pin: pin);
      widget.onDone();
    } else {
      setState(() {
        _step = 2;
        _first = null;
        _error = "Those PINs didn't match. Try again.";
      });
      _confirmKey.currentState?.shake();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget body;
    switch (_step) {
      case 0:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Protect your journal', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Your journal asks for a PIN every time it opens. Which PIN do you want?',
              textAlign: TextAlign.center, style: tt.bodyMedium),
          const SizedBox(height: 22),
          _Choice(
            icon: Icons.lock_outline_rounded,
            title: 'Use my app PIN',
            subtitle: 'Same PIN you already use to open MyDay',
            onTap: _useAppPin,
          ),
          const SizedBox(height: 12),
          _Choice(
            icon: Icons.key_rounded,
            title: 'Use a separate journal PIN',
            subtitle: 'A different PIN just for your journal',
            onTap: () => setState(() => _step = 1),
          ),
        ]);
      case 1:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Text('How long should the PIN be?', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 4, label: Text('4 digits')),
              ButtonSegment(value: 6, label: Text('6 digits')),
            ],
            selected: {_length},
            onSelectionChanged: (v) => setState(() => _length = v.first),
          ),
          const SizedBox(height: 22),
          FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('Next')),
          TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Back')),
        ]);
      default:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_step == 2 ? 'Create your journal PIN' : 'Type it again to confirm',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          PinPad(key: _step == 2 ? _createKey : _confirmKey, length: _length, onComplete: _onPin),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
        ]);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Glass(
            blur: true,
            radius: 28,
            padding: const EdgeInsets.all(26),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: KeyedSubtree(key: ValueKey(_step), child: body),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, color: cs.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────── the book opening + PIN ─────────────────────────

class _BookOpening extends StatefulWidget {
  const _BookOpening({super.key, required this.anim, required this.onUnlocked});
  final AnimationController anim;
  final VoidCallback onUnlocked;

  @override
  State<_BookOpening> createState() => _BookOpeningState();
}

class _BookOpeningState extends State<_BookOpening> {
  final _pinKey = GlobalKey<PinPadState>();
  bool _askQuestion = false;
  final _answer = TextEditingController();
  String? _error;
  bool _showHint = false;
  bool _resetting = false;
  String? _firstNew;
  bool _bioBusy = false;

  @override
  void initState() {
    super.initState();
    widget.anim.addStatusListener(_onAnim);
    if (widget.anim.status == AnimationStatus.completed) WidgetsBinding.instance.addPostFrameCallback((_) => _tryBio());
  }

  void _onAnim(AnimationStatus st) {
    if (st == AnimationStatus.completed) _tryBio(); // the book is open: offer the fingerprint
  }

  Future<void> _tryBio() async {
    final s = context.read<SettingsService>();
    if (_bioBusy || !s.bioJournal || !mounted || !context.read<JournalLock>().needsPin) return;
    if (_askQuestion || _resetting) return;
    _bioBusy = true;
    final ok = await context.read<BiometricService>().authenticate('Open your journal');
    _bioBusy = false;
    if (ok && mounted) widget.onUnlocked();
  }

  @override
  void dispose() {
    widget.anim.removeStatusListener(_onAnim);
    _answer.dispose();
    super.dispose();
  }

  void _onPin(String pin) {
    final lock = context.read<JournalLock>();
    if (lock.tryPin(pin)) {
      widget.onUnlocked();
      return;
    }
    _pinKey.currentState?.shake();
    final left = 5 - lock.failedAttempts;
    setState(() {
      if (left <= 0) {
        _askQuestion = true;
        _error = null;
      } else {
        _error = 'Wrong PIN. $left ${left == 1 ? 'try' : 'tries'} left.';
      }
    });
  }

  void _checkAnswer() {
    final s = context.read<SettingsService>();
    if (!s.verifyAnswer(_answer.text)) {
      setState(() => _error = 'That answer is not right.');
      return;
    }
    if (s.journalMode == 'own') {
      setState(() {
        _resetting = true;
        _error = null;
      });
    } else {
      widget.onUnlocked();
    }
  }

  Future<void> _onNewPin(String pin) async {
    if (_firstNew == null) {
      setState(() => _firstNew = pin);
      _pinKey.currentState?.clear();
    } else if (_firstNew == pin) {
      final s = context.read<SettingsService>();
      await s.setJournalPin(pin, s.journalPinLen);
      widget.onUnlocked();
    } else {
      setState(() {
        _firstNew = null;
        _error = "PINs didn't match. Try again.";
      });
      _pinKey.currentState?.shake();
    }
  }

  Widget _page(BuildContext context) {
    final s = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final needsPin = context.read<JournalLock>().needsPin;
    if (!needsPin) {
      return Center(child: Text('Opening your journal…', style: tt.titleMedium));
    }
    Widget content;
    if (_resetting) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_firstNew == null ? 'Set a new journal PIN' : 'Confirm your new PIN', style: tt.titleLarge),
        const SizedBox(height: 16),
        PinPad(key: _pinKey, length: s.journalPinLen, onComplete: _onNewPin),
      ]);
    } else if (_askQuestion) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Too many wrong tries.\nAnswer your security question to continue.',
            textAlign: TextAlign.center, style: tt.bodyMedium),
        const SizedBox(height: 14),
        Text(s.securityQuestion, style: tt.titleMedium),
        const SizedBox(height: 10),
        TextField(
          controller: _answer,
          decoration: const InputDecoration(labelText: 'Your answer'),
          onSubmitted: (_) => _checkAnswer(),
        ),
        if (s.securityHint.isNotEmpty)
          _showHint
              ? Padding(padding: const EdgeInsets.only(top: 8), child: Text('Hint: ${s.securityHint}'))
              : TextButton.icon(
                  onPressed: () => setState(() => _showHint = true),
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Show hint')),
        const SizedBox(height: 10),
        FilledButton(onPressed: _checkAnswer, child: const Text('Continue')),
      ]);
    } else {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline_rounded, color: cs.primary, size: 30),
        const SizedBox(height: 6),
        Text('Enter your ${s.journalMode == 'own' ? 'journal' : 'app'} PIN', style: tt.titleMedium),
        const SizedBox(height: 14),
        PinPad(key: _pinKey, length: s.journalMode == 'own' ? s.journalPinLen : 4, onComplete: _onPin),
        if (s.bioJournal)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.fingerprint, size: 26),
              label: const Text('Use fingerprint'),
              onPressed: _tryBio,
            ),
          ),
      ]);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            content,
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anim = widget.anim;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (anim.isAnimating) anim.value = 1; // tap to skip the animation
      },
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.value;
          // timeline: appear (0-0.25), cover opens (0.25-0.8), page revealed (0.8-1)
          final appear = Curves.easeOut.transform((t / 0.25).clamp(0.0, 1.0));
          final open = Curves.easeInOutCubic.transform(((t - 0.25) / 0.55).clamp(0.0, 1.0));
          final coverAngle = open * math.pi * 0.62;
          final coverOpacity = (1 - ((open - 0.55) / 0.35).clamp(0.0, 1.0));
          final pageAlpha = ((t - 0.45) / 0.35).clamp(0.0, 1.0);

          return LayoutBuilder(builder: (context, c) {
            final bookW = math.min(c.maxWidth - 48, 360.0);
            final bookH = math.min(c.maxHeight - 48, bookW * 1.38);
            final w = bookW * (0.55 + 0.45 * appear);
            final h = bookH * (0.55 + 0.45 * appear);
            return Stack(alignment: Alignment.center, children: [
              // the page under the cover (PIN or "opening…")
              Opacity(
                opacity: pageAlpha,
                child: IgnorePointer(ignoring: pageAlpha < 0.9, child: _page(context)),
              ),
              if (coverOpacity > 0)
                Opacity(
                  opacity: appear * coverOpacity,
                  child: Center(
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Transform(
                        alignment: Alignment.centerLeft,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0013)
                          ..rotateY(-coverAngle),
                        child: const JournalCover(),
                      ),
                    ),
                  ),
                ),
            ]);
          });
        },
      ),
    );
  }
}

/// The leather cover of the journal.
class JournalCover extends StatelessWidget {
  const JournalCover({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = HSLColor.fromColor(cs.primary);
    final dark = base.withLightness(0.22).withSaturation(0.6).toColor();
    final light = base.withLightness(0.38).withSaturation(0.55).toColor();
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(topRight: Radius.circular(18), bottomRight: Radius.circular(18), topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, dark]),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 36, offset: const Offset(10, 18)),
        ],
      ),
      child: Stack(children: [
        // spine shading on the left
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 26,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
              gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent]),
            ),
          ),
        ),
        // gold frame
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 22, 22, 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE9C46A).withValues(alpha: 0.75), width: 1.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset('assets/icon.png', width: 64, height: 64)),
                  const SizedBox(height: 16),
                  const Text('Journal',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: Color(0xFFF4D58D))),
                  const SizedBox(height: 6),
                  Container(width: 54, height: 2, color: const Color(0xFFE9C46A).withValues(alpha: 0.8)),
                  const SizedBox(height: 8),
                  Text('private & locked',
                      style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.7))),
                ]),
              ),
            ),
          ),
        ),
        // ribbon bookmark
        Positioned(
          right: 34,
          top: 0,
          child: Container(
            width: 18,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFE76F51),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
            ),
          ),
        ),
      ]),
    );
  }
}
