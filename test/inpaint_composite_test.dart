import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crayon/core/imaging.dart';

/// Renders a solid colour, optionally with a filled white circle, to PNG bytes.
Future<Uint8List> _png(int w, int h, Color bg, {Color? dot, double r = 0}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = bg);
  if (dot != null && r > 0) {
    canvas.drawCircle(Offset(w / 2, h / 2), r, Paint()..color = dot);
  }
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  pic.dispose();
  img.dispose();
  return bd!.buffer.asUint8List();
}

Future<List<int>> _pixel(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final bd = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = frame.image.width;
  frame.image.dispose();
  codec.dispose();
  final i = (y * w + x) * 4;
  final b = bd!.buffer.asUint8List();
  return [b[i], b[i + 1], b[i + 2], b[i + 3]];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('crayon_inpaint'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String name, Uint8List bytes) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return f;
  }

  test('composite keeps the original outside the mask and takes the new pixels inside', () async {
    const w = 200, h = 200;
    final original = write('o.png', await _png(w, h, const Color(0xFF0000FF))); // blue
    final generated = await _png(w, h, const Color(0xFFFF0000)); // red
    // mask: white circle in the middle on black
    final mask = write('m.png', await _png(w, h, const Color(0xFF000000), dot: const Color(0xFFFFFFFF), r: 50));

    final out = await Imaging.compositeInpaint(
      original: original,
      generated: generated,
      mask: mask,
      feather: 0,
    );
    expect(out, isNotNull);

    // dead centre is inside the mask: must be the generated red
    final centre = await _pixel(out!, 100, 100);
    expect(centre[0], greaterThan(200), reason: 'centre should be red');
    expect(centre[2], lessThan(60), reason: 'centre should not still be blue');

    // corners are far outside the mask: must be the ORIGINAL blue, untouched
    for (final p in [[3, 3], [w - 4, 3], [3, h - 4], [w - 4, h - 4]]) {
      final px = await _pixel(out, p[0], p[1]);
      expect(px[2], greaterThan(200), reason: "corner $p must stay blue");
      expect(px[0], lessThan(60), reason: "corner $p must not pick up red");
    }
  });

  test('an all black mask changes nothing at all', () async {
    const w = 120, h = 120;
    final original = write('o.png', await _png(w, h, const Color(0xFF00FF00)));
    final generated = await _png(w, h, const Color(0xFFFF0000));
    final mask = write('m.png', await _png(w, h, const Color(0xFF000000)));

    final out = await Imaging.compositeInpaint(
        original: original, generated: generated, mask: mask, feather: 0);
    final centre = await _pixel(out!, 60, 60);
    expect(centre[1], greaterThan(200), reason: 'still green');
    expect(centre[0], lessThan(60), reason: 'no red leaked in');
  });

  test('a differently sized generated image is scaled to the original', () async {
    final original = write('o.png', await _png(300, 150, const Color(0xFF0000FF)));
    // model returned a square, as Seedream did in testing
    final generated = await _png(512, 512, const Color(0xFFFF0000));
    final mask = write('m.png',
        await _png(300, 150, const Color(0xFF000000), dot: const Color(0xFFFFFFFF), r: 40));

    final out = await Imaging.compositeInpaint(
        original: original, generated: generated, mask: mask, feather: 0);
    expect(out, isNotNull);
    // output keeps the ORIGINAL dimensions, not the model's
    final codec = await ui.instantiateImageCodec(out!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 300);
    expect(frame.image.height, 150);
    frame.image.dispose();
    codec.dispose();
  });

  test('maskHasContent tells an empty mask from a painted one', () async {
    final empty = write('e.png', await _png(200, 200, const Color(0xFF000000)));
    final painted = write('p.png',
        await _png(200, 200, const Color(0xFF000000), dot: const Color(0xFFFFFFFF), r: 70));
    expect(await Imaging.maskHasContent(empty), isFalse);
    expect(await Imaging.maskHasContent(painted), isTrue);
  });

  test('the marked input carries a magenta patch where the mask is', () async {
    const w = 200, h = 200;
    final src = write('s.png', await _png(w, h, const Color(0xFF222222)));
    final mask = write('m.png',
        await _png(w, h, const Color(0xFF000000), dot: const Color(0xFFFFFFFF), r: 60));
    final marked = await Imaging.buildInpaintInput(src, mask);
    expect(marked, isNotNull);
    final centre = await _pixel(marked!, 100, 100);
    expect(centre[0], greaterThan(200), reason: 'magenta R');
    expect(centre[2], greaterThan(200), reason: 'magenta B');
    expect(centre[1], lessThan(60), reason: 'magenta has no green');
    final corner = await _pixel(marked, 4, 4);
    expect(corner[0], lessThan(60), reason: 'outside the mask stays the source');
  });
}
