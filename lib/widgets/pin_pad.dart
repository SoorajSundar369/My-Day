import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fx.dart';

/// 4-digit PIN entry with glowing dots, 3D keys and keyboard support.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onComplete, this.autofocus = true, this.length = 4});

  final ValueChanged<String> onComplete;
  final bool autofocus;

  /// Number of digits (4 or 6).
  final int length;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  final _focus = FocusNode();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  void clear() => setState(() => _pin = '');

  /// Wiggles the dots (call after a wrong PIN) and clears the entry.
  void shake() {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    clear();
  }

  void _add(String d) {
    if (_pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final p = _pin;
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) widget.onComplete(p);
      });
    }
  }

  void _back() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    final c = e.character;
    if (c != null && c.length == 1 && '0123456789'.contains(c)) {
      _add(c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _focus.requestFocus,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) => Transform.translate(
              offset: Offset(math.sin(_shake.value * math.pi * 6) * 14 * (1 - _shake.value), 0),
              child: child,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic, // no overshoot: the glow radius must never go negative
                  margin: const EdgeInsets.all(9),
                  width: i < _pin.length ? 20 : 16,
                  height: i < _pin.length ? 20 : 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: i < _pin.length ? LinearGradient(colors: [cs.primary, cs.tertiary]) : null,
                    border: Border.all(color: cs.primary.withValues(alpha: 0.7), width: 2),
                    boxShadow: i < _pin.length
                        ? [BoxShadow(color: cs.primary.withValues(alpha: 0.6), blurRadius: 14)]
                        : null,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 22),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final d in row) _Key(label: d, onTap: () => _add(d)),
            ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const _Key(label: '', onTap: null),
            _Key(label: '0', onTap: () => _add('0')),
            _Key(label: '', icon: Icons.backspace_outlined, onTap: _back),
          ]),
        ]),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return const SizedBox(width: 84, height: 76);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final m = Motion.of(context);
    final lift = _down ? 0.0 : (_hover ? 7.0 : 5.0) * m.depth;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: 84,
          height: 76,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              transformAlignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateX(_down ? 0.0 : -0.12 * m.depth)
                ..translate(0.0, _down ? 3.0 * m.depth : 0.0),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [Colors.white.withValues(alpha: _hover ? 0.2 : 0.14), Colors.white.withValues(alpha: 0.05)]
                      : [Colors.white, Colors.white.withValues(alpha: 0.6)],
                ),
                border: Border.all(
                    color: dark ? Colors.white.withValues(alpha: 0.18) : Colors.white, width: 1),
                boxShadow: [
                  BoxShadow(
                      color: (dark ? Colors.black : cs.primary).withValues(alpha: dark ? 0.55 : 0.22),
                      blurRadius: 6 + lift * 2,
                      offset: Offset(0, lift)),
                ],
              ),
              child: Center(
                child: widget.icon != null
                    ? Icon(widget.icon, color: cs.onSurface)
                    : Text(widget.label,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: cs.onSurface)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
