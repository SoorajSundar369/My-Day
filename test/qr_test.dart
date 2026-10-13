import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:taskme/sync/qr_decode.dart';

void main() {
  testWidgets('a QR code on a phone screen photographed by a webcam can be read', (t) async {
    final payload = jsonEncode({'v': 2, 'id': 'phone-id', 'n': 'My phone', 'k': 'QFsdeGpUYD0SZqzFEo4kMkkwmqBhBdxMMICCyiyT0kE=', 't': 'abc123xyz9'});
    late Uint8List png;
    await t.runAsync(() async {
      final painter = QrPainter(data: payload, version: QrVersions.auto, gapless: false, color: Colors.black, emptyColor: Colors.white);
      final data = await painter.toImageData(420, format: ui.ImageByteFormat.png);
      png = data!.buffer.asUint8List();
    });

    // plain QR
    expect(decodeQrFromImage(png), payload);

    // a more realistic "photo": QR sits small in a grey scene, as a JPEG, and mirrored like some webcams
    final qr = img.decodePng(png)!;
    final scene = img.Image(width: 1280, height: 720);
    img.fill(scene, color: img.ColorRgb8(110, 110, 120));
    img.compositeImage(scene, img.copyResize(qr, width: 380), dstX: 450, dstY: 140);
    final mirrored = img.flipHorizontal(scene);
    final jpg = Uint8List.fromList(img.encodeJpg(mirrored, quality: 80));
    expect(decodeQrFromImage(jpg), payload);

    // nothing to read
    expect(decodeQrFromImage(Uint8List.fromList(img.encodeJpg(img.Image(width: 300, height: 300)))), isNull);
    expect(decodeQrFromImage(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
