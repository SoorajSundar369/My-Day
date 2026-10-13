import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';

/// How much animation the user wants (Settings > Animations).
class Motion {
  const Motion(this.level);
  final int level; // 0 off, 1 subtle, 2 balanced, 3 bold

  bool get on => level > 0;
  bool get ambient => level >= 2; // moving backgrounds, floating icon
  bool get celebrate => level >= 2;
  double get tilt => const [0.0, 3.0, 7.0, 12.0][level]; // max card tilt in degrees
  double get depth => const [0.0, 0.4, 0.75, 1.0][level]; // shadow / lift strength
  Duration ms(int v) => on ? Duration(milliseconds: v) : Duration.zero;

  static Motion of(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return const Motion(0);
    return Motion(context.watch<SettingsService>().motionLevel);
  }
}

// ───────────────────────── Aurora background ─────────────────────────

/// Slowly drifting colour glows behind the whole app.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 50));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (motion.ambient && !_c.isAnimating) {
      _c.repeat();
    } else if (!motion.ambient && _c.isAnimating) {
      _c.stop();
    }
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
        child: CustomPaint(
          painter: _AuroraPainter(_c, accent, dark),
          size: Size.infinite,
        ),
      ),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t, this.accent, this.dark) : super(repaint: t);
  final Animation<double> t;
  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final hsl = HSLColor.fromColor(accent);
    final base = dark ? const Color(0xFF080A16) : const Color(0xFFF2F3FB);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final a = t.value * 2 * math.pi;
    final big = math.max(size.width, size.height);
    final colors = [
      hsl.withLightness(dark ? 0.5 : 0.62).withSaturation(0.85).toColor(),
      hsl.withHue((hsl.hue + 70) % 360).withLightness(dark ? 0.45 : 0.68).withSaturation(0.8).toColor(),
      hsl.withHue((hsl.hue + 300) % 360).withLightness(dark ? 0.45 : 0.7).withSaturation(0.8).toColor(),
    ];
    final alpha = dark ? 0.42 : 0.30;
    final blobs = [
      (0.18 + 0.10 * math.sin(a), 0.15 + 0.10 * math.cos(a), 0.65, colors[0]),
      (0.85 + 0.08 * math.cos(a * 1.0 + 1), 0.30 + 0.12 * math.sin(a + 2), 0.6, colors[1]),
      (0.55 + 0.12 * math.sin(a + 4), 0.92 + 0.06 * math.cos(a + 1), 0.7, colors[2]),
    ];
    for (final (x, y, r, c) in blobs) {
      final center = Offset(size.width * x, size.height * y);
      final radius = big * r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
              center, radius, [c.withValues(alpha: alpha), c.withValues(alpha: 0)]),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.accent != accent || old.dark != dark;
}

// ───────────────────────── Glass ─────────────────────────

/// Frosted glass panel with a soft border and depth shadow.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = false,
    this.onTap,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final m = Motion.of(context);
    final br = BorderRadius.circular(radius);
    final deco = BoxDecoration(
      borderRadius: br,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.04)]
            : [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.55)],
      ),
      color: tint?.withValues(alpha: 0.12),
      border: Border.all(
          color: dark ? Colors.white.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.9),
          width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: (dark ? 0.35 : 0.08) * (0.4 + 0.6 * m.depth)),
          blurRadius: 24 * (0.5 + m.depth),
          offset: Offset(0, 10 * (0.5 + m.depth)),
        ),
      ],
    );
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(borderRadius: br, onTap: onTap, child: body);
    }
    body = Material(color: Colors.transparent, borderRadius: br, child: body);
    Widget box = DecoratedBox(decoration: deco, child: body);
    final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    if (blur && !(mobile && m.level < 3)) {
      box = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: box),
      );
    }
    return box;
  }
}

// ───────────────────────── 3D tilt ─────────────────────────

/// Tilts its child in 3D towards the mouse pointer, with a lift on hover.
class Tilt extends StatefulWidget {
  const Tilt({super.key, required this.child, this.strength = 1.0, this.lift = true});
  final Widget child;
  final double strength;
  final bool lift;

  @override
  State<Tilt> createState() => _TiltState();
}

class _TiltState extends State<Tilt> {
  Offset _o = Offset.zero; // -0.5 .. 0.5 from the centre
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    if (m.tilt == 0) return widget.child;
    final max = m.tilt * widget.strength * math.pi / 180;
    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final p = e.localPosition;
        setState(() {
          _hover = true;
          _o = Offset(p.dx / box.size.width - 0.5, p.dy / box.size.height - 0.5);
        });
      },
      onExit: (_) => setState(() {
        _hover = false;
        _o = Offset.zero;
      }),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: _o),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        builder: (context, o, child) {
          final scale = _hover && widget.lift ? 1.0 + 0.025 * m.depth : 1.0;
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateX(-o.dy * max * 2)
            ..rotateY(o.dx * max * 2)
            ..scale(scale, scale, scale);
          return Transform(alignment: Alignment.center, transform: matrix, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

// ───────────────────────── Reveal (entrance) ─────────────────────────

/// Fades + slides + slightly rotates its child in; stagger with [index].
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 26});
  final Widget child;
  final int index;
  final double dy;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final m = Motion.of(context);
    if (!m.on) {
      _c.value = 1;
      return;
    }
    _c.duration = const Duration(milliseconds: 650);
    Future.delayed(Duration(milliseconds: 55 * widget.index.clamp(0, 9)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) {
        final t = curve.value;
        if (t >= 1) return child!;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..translate(0.0, (1 - t) * widget.dy)
              ..rotateX((1 - t) * 0.18),
            child: child,
          ),
        );
      },
    );
  }
}

// ───────────────────────── Count-up numbers ─────────────────────────

class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, required this.format, this.style});
  final double value;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: m.ms(900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(format(v), style: style),
    );
  }
}

// ───────────────────────── Progress ring ─────────────────────────

class AnimatedRing extends StatelessWidget {
  const AnimatedRing({
    super.key,
    required this.value,
    this.size = 72,
    this.stroke = 9,
    this.colors,
    this.child,
  });

  final double value; // 0..1
  final double size;
  final double stroke;
  final List<Color>? colors;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    final cs = Theme.of(context).colorScheme;
    final cols = colors ?? [cs.primary, cs.tertiary];
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: m.ms(1100),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, cols, cs.onSurface.withValues(alpha: 0.10), m.depth),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.colors, this.track, this.glow);
  final double v, stroke, glow;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);
    if (v <= 0) return;
    final sweep = 2 * math.pi * v;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [...colors, colors.first],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);
    if (glow > 0) {
      canvas.drawArc(
          rect,
          -math.pi / 2,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..shader = shader
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.9 * glow));
    }
    canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.colors != colors || o.track != track;
}

// ───────────────────────── Press feedback ─────────────────────────

/// Squashes slightly while pressed, like a physical button.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap, this.scale = 0.94});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down && m.on ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ───────────────────────── Floating 3D icon ─────────────────────────

/// Slowly rocks in 3D and follows the mouse; used for the app icon.
class FloatingIcon extends StatefulWidget {
  const FloatingIcon({super.key, required this.size, this.radius});
  final double size;
  final double? radius;

  @override
  State<FloatingIcon> createState() => _FloatingIconState();
}

class _FloatingIconState extends State<FloatingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Offset _o = Offset.zero;

  @override
  void initState() {
    super.initState();
    // Created up front (not lazily) so closing the screen never has to create it.
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = Motion.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = widget.radius ?? widget.size * 0.225;
    final icon = ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Image.asset('assets/icon.png', width: widget.size, height: widget.size),
    );
    if (!m.ambient) {
      if (_c.isAnimating) _c.stop();
      return icon;
    }
    if (!_c.isAnimating) _c.repeat();
    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        setState(() => _o = Offset(e.localPosition.dx / box.size.width - 0.5,
            e.localPosition.dy / box.size.height - 0.5));
      },
      onExit: (_) => setState(() => _o = Offset.zero),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final a = _c.value * 2 * math.pi;
          final bob = math.sin(a) * 6;
          final m4 = Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..translate(0.0, bob)
            ..rotateX(math.sin(a + 1) * 0.10 - _o.dy * 0.7)
            ..rotateY(math.cos(a) * 0.16 + _o.dx * 0.7);
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: widget.size * 0.9,
              height: widget.size * 0.9,
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                BoxShadow(
                    color: cs.primary.withValues(alpha: 0.55),
                    blurRadius: 50 + 10 * math.sin(a),
                    spreadRadius: 4),
              ]),
            ),
            Transform(alignment: Alignment.center, transform: m4, child: child),
          ]);
        },
        child: icon,
      ),
    );
  }
}

// ───────────────────────── Celebration burst ─────────────────────────

/// Confetti burst from the centre of [context]'s widget.
void celebrate(BuildContext context) {
  final m = Motion.of(context);
  if (!m.celebrate) return;
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.maybeOf(context);
  if (box == null || !box.hasSize || overlay == null) return;
  final origin = box.localToGlobal(box.size.center(Offset.zero));
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Burst(origin: origin, bold: m.level >= 3, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Burst extends StatefulWidget {
  const _Burst({required this.origin, required this.bold, required this.onDone});
  final Offset origin;
  final bool bold;
  final VoidCallback onDone;

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..forward().whenComplete(widget.onDone);
  late final List<_Particle> _ps;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    final n = widget.bold ? 46 : 26;
    _ps = List.generate(n, (_) {
      final ang = rnd.nextDouble() * 2 * math.pi;
      return _Particle(
        angle: ang,
        speed: 90 + rnd.nextDouble() * (widget.bold ? 230 : 150),
        size: 4 + rnd.nextDouble() * 5,
        hue: rnd.nextDouble() * 360,
        spin: rnd.nextDouble() * 6,
        round: rnd.nextBool(),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BurstPainter(_c, widget.origin, _ps),
      ),
    );
  }
}

class _Particle {
  _Particle(
      {required this.angle,
      required this.speed,
      required this.size,
      required this.hue,
      required this.spin,
      required this.round});
  final double angle, speed, size, hue, spin;
  final bool round;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.origin, this.ps) : super(repaint: t);
  final Animation<double> t;
  final Offset origin;
  final List<_Particle> ps;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final ease = Curves.easeOutCubic.transform(v);
    for (final p in ps) {
      final dx = math.cos(p.angle) * p.speed * ease;
      final dy = math.sin(p.angle) * p.speed * ease + 220 * v * v; // gravity
      final pos = origin + Offset(dx, dy);
      final paint = Paint()
        ..color = HSLColor.fromAHSL((1 - v).clamp(0.0, 1.0), p.hue, 0.9, 0.62).toColor();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * v * 6);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: p.size * 1.6, height: p.size * 0.8),
                const Radius.circular(2)),
            paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => true;
}

// ───────────────────────── Gradient text ─────────────────────────

class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(colors: [cs.primary, cs.tertiary, cs.secondary]).createShader(r),
      child: Text(text, style: style),
    );
  }
}

/// Wraps every item in a staggered [Reveal].
List<Widget> revealAll(List<Widget> items, {int start = 0}) => [
      for (var i = 0; i < items.length; i++) Reveal(index: start + i, child: items[i]),
    ];
