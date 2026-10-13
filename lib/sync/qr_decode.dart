import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Reads a QR code from a photo (JPEG/PNG bytes). Returns its text, or null if none was found.
/// Pure Dart, so it also works on Windows where camera streaming is not available.
String? decodeQrFromImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null; // not a picture at all
  }
  if (decoded == null) return null;
  // Smaller is faster, and a phone screen QR is big enough at this size.
  final photo = decoded.width > 1000 ? img.copyResize(decoded, width: 1000) : decoded;

  String? tryDecode(img.Image image) {
    final w = image.width, h = image.height;
    final pixels = Int32List(w * h);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        pixels[i++] = (0xFF << 24) | (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
      }
    }
    final bitmap = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(w, h, pixels)));
    try {
      return QRCodeReader().decode(bitmap, hints: DecodeHints()..put(DecodeHintType.tryHarder)).text;
    } catch (_) {
      return null;
    }
  }

  // Webcams often mirror the picture; a mirrored QR code does not read, so try both ways.
  return tryDecode(photo) ?? tryDecode(img.flipHorizontal(photo.clone()));
}
