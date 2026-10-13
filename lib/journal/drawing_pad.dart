import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class _Stroke {
  _Stroke(this.color, this.width, this.erase);
  final Color color;
  final double width;
  final bool erase;
  final points = <Offset>[];
}

const _paper = Color(0xFFFFFCF5);

/// A page you can write or draw on with a finger, a stylus or the mouse.
/// Returns the picture as PNG bytes.
class DrawingPad extends StatefulWidget {
  const DrawingPad({super.key});

  @override
  State<DrawingPad> createState() => _DrawingPadState();
}

class _DrawingPadState extends State<DrawingPad> {
  final _strokes = <_Stroke>[];
  Color _color = const Color(0xFF1B1B1F);
  double _width = 3.5;
  bool _erase = false;
  Size _size = Size.zero;

  static const _colors = [Color(0xFF1B1B1F), Color(0xFF1D4ED8), Color(0xFFDC2626), Color(0xFF15803D), Color(0xFFB45309)];

  void _start(Offset p) {
    final s = _Stroke(_color, _erase ? _width * 4 : _width, _erase)..points.add(p);
    setState(() => _strokes.add(s));
  }

  void _add(Offset p) => setState(() => _strokes.last.points.add(p));

  Future<void> _done() async {
    if (_strokes.isEmpty || _size.isEmpty) {
      Navigator.pop(context);
      return;
    }
    const outW = 1400.0;
    final scale = outW / _size.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    _PadPainter(_strokes).paint(canvas, _size);
    final image = await recorder.endRecording().toImage(outW.round(), (_size.height * scale).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (mounted) Navigator.pop<Uint8List>(context, bytes!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Write or draw'),
        actions: [
          IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo_rounded),
              onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast)),
          IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear)),
          TextButton(onPressed: _done, child: const Text('Done')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: LayoutBuilder(builder: (context, c) {
                _size = Size(c.maxWidth, c.maxHeight);
                return GestureDetector(
                  onPanStart: (d) => _start(d.localPosition),
                  onPanUpdate: (d) => _add(d.localPosition),
                  child: CustomPaint(painter: _PadPainter(_strokes), size: Size.infinite),
                );
              }),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => setState(() {
                    _color = c;
                    _erase = false;
                  }),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: !_erase && _color == c ? cs.primary : Colors.transparent, width: 3),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Eraser'),
                avatar: const Icon(Icons.auto_fix_normal_rounded, size: 18),
                selected: _erase,
                onSelected: (v) => setState(() => _erase = v),
              ),
              SizedBox(
                width: 160,
                child: Slider(min: 1.5, max: 12, value: _width, onChanged: (v) => setState(() => _width = v)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);
    // faint ruled lines, like a notebook page
    final line = Paint()..color = const Color(0xFFE8E2D2)..strokeWidth = 1;
    for (var y = 40.0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.erase ? _paper : s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
      } else {
        final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
        for (var i = 1; i < s.points.length; i++) {
          final mid = (s.points[i - 1] + s.points[i]) / 2;
          path.quadraticBezierTo(s.points[i - 1].dx, s.points[i - 1].dy, mid.dx, mid.dy);
        }
        path.lineTo(s.points.last.dx, s.points.last.dy);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
