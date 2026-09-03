import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class ImgSize {
  const ImgSize(this.width, this.height);
  final int width;
  final int height;
}

class Imaging {
  static Future<ImgSize> size(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final s = ImgSize(frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return s;
    } catch (_) {
      return const ImgSize(0, 0);
    }
  }

  static String mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.mp4')) return 'video/mp4';
    return 'image/png';
  }

  /// OpenRouter accepts base64 data URLs for reference images.
  static Future<String> toDataUrl(File f) async {
    final bytes = await f.readAsBytes();
    return 'data:${mimeFor(f.path)};base64,${base64Encode(bytes)}';
  }

  /// Re-encodes a reference down to [maxSide] before upload.
  ///
  /// Pass 0 to send the file untouched at full resolution. The cap exists only
  /// because a 12MP photo as base64 is a ~16MB request body, which is slow on
  /// mobile data. It is a bandwidth trade, not a quality judgement, so it is a
  /// setting rather than a hardcoded number.
  static Future<String> toDataUrlCompressed(File f, {int maxSide = 2048, int quality = 95}) async {
    if (maxSide <= 0) {
      final bytes = await f.readAsBytes();
      return 'data:${mimeFor(f.path)};base64,${base64Encode(bytes)}';
    }
    try {
      final raw = await f.readAsBytes();
      final codec = await ui.instantiateImageCodec(raw, targetWidth: null);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final longest = img.width > img.height ? img.width : img.height;
      if (longest <= maxSide) {
        img.dispose();
        codec.dispose();
        return 'data:${mimeFor(f.path)};base64,${base64Encode(raw)}';
      }
      final scale = maxSide / longest;
      final tw = (img.width * scale).round();
      final th = (img.height * scale).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final pic = recorder.endRecording();
      final out = await pic.toImage(tw, th);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      out.dispose();
      pic.dispose();
      codec.dispose();
      if (bd == null) return 'data:${mimeFor(f.path)};base64,${base64Encode(raw)}';
      return 'data:image/png;base64,${base64Encode(bd.buffer.asUint8List())}';
    } catch (_) {
      final bytes = await f.readAsBytes();
      return 'data:${mimeFor(f.path)};base64,${base64Encode(bytes)}';
    }
  }

  static (int, int) parseAspect(String ar) {
    final parts = ar.split(':');
    if (parts.length != 2) return (1, 1);
    final w = double.tryParse(parts[0]) ?? 1;
    final h = double.tryParse(parts[1]) ?? 1;
    return ((w * 100).round(), (h * 100).round());
  }

  /// Builds the canvas an outpaint needs: the source image placed inside a
  /// larger frame of the target aspect ratio, with the new area left blank for
  /// the model to fill. This is a real client-side composite, not a prompt
  /// trick, and it is why outpaint works on models that expose no mask input.
  ///
  /// Returns PNG bytes.
  static Future<Uint8List?> buildOutpaintCanvas(
    File src, {
    required String targetAspect,
    double zoomOut = 1.0,
    Color fill = const Color(0x00000000),
  }) async {
    try {
      final raw = await src.readAsBytes();
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final (aw, ah) = parseAspect(targetAspect);
      final targetRatio = aw / ah;
      final srcRatio = img.width / img.height;

      // Fit the source inside a canvas of the target ratio, then apply the
      // extra zoom-out so there is room to paint even when ratios match.
      double cw, ch;
      if (targetRatio >= srcRatio) {
        ch = img.height.toDouble();
        cw = ch * targetRatio;
      } else {
        cw = img.width.toDouble();
        ch = cw / targetRatio;
      }
      cw *= zoomOut;
      ch *= zoomOut;

      // keep the canvas within a sane upload size
      const maxSide = 4096.0;
      final longest = cw > ch ? cw : ch;
      if (longest > maxSide) {
        final s = maxSide / longest;
        cw *= s;
        ch *= s;
      }

      // Scale the source to fit inside the canvas, preserving its own ratio.
      // Dividing by zoomOut leaves a uniform margin for the model to fill.
      final fitScale =
          ((cw / img.width) < (ch / img.height) ? (cw / img.width) : (ch / img.height)) / zoomOut;
      final dw = img.width * fitScale;
      final dh = img.height * fitScale;
      final dx = (cw - dw) / 2;
      final dy = (ch - dh) / 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (fill.a > 0) {
        canvas.drawRect(Rect.fromLTWH(0, 0, cw, ch), Paint()..color = fill);
      }
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(dx, dy, dw, dh),
        Paint()..filterQuality = FilterQuality.high,
      );
      final pic = recorder.endRecording();
      final out = await pic.toImage(cw.round(), ch.round());
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      out.dispose();
      pic.dispose();
      codec.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Marks the masked region visibly in the source image so an API with no
  /// mask parameter can still be told WHERE to work. The model sees a solid
  /// magenta patch and the prompt tells it to replace exactly that area.
  static Future<Uint8List?> buildInpaintInput(File src, File mask) async {
    try {
      final (img, mk) = await _decodePair(src, mask);
      if (img == null || mk == null) return null;
      final w = img.width, h = img.height;
      final full = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImageRect(img, full, full, Paint()..filterQuality = FilterQuality.high);
      canvas.saveLayer(full, Paint());
      canvas.drawRect(full, Paint()..color = const Color(0xFFFF00FF));
      canvas.drawImageRect(
        mk,
        Rect.fromLTWH(0, 0, mk.width.toDouble(), mk.height.toDouble()),
        full,
        Paint()
          ..colorFilter = _luminanceToAlpha
          ..blendMode = BlendMode.dstIn,
      );
      canvas.restore();

      final pic = rec.endRecording();
      final out = await pic.toImage(w, h);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      mk.dispose();
      out.dispose();
      pic.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// THE step that makes inpainting real.
  ///
  /// These models regenerate the whole frame even when handed a mask, so the
  /// result is composited back over the original through the mask:
  ///   out = mask * generated + (1 - mask) * original
  /// Original pixels are pasted straight back, so everything outside the mask
  /// survives byte for byte. The mask is blurred a few pixels so the join does
  /// not show as a hard seam.
  static Future<Uint8List?> compositeInpaint({
    required File original,
    required Uint8List generated,
    required File mask,
    double feather = 6,
  }) async {
    try {
      final baseBytes = await original.readAsBytes();
      final base = await _decode(baseBytes);
      final gen = await _decode(generated);
      final mk = await _decode(await mask.readAsBytes());
      if (base == null || gen == null || mk == null) return null;

      final w = base.width, h = base.height;
      final full = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      // everything outside the mask comes from the untouched original
      canvas.drawImageRect(base, full, full, Paint()..filterQuality = FilterQuality.high);

      canvas.saveLayer(full, Paint());
      canvas.drawImageRect(
        gen,
        Rect.fromLTWH(0, 0, gen.width.toDouble(), gen.height.toDouble()),
        full,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.drawImageRect(
        mk,
        Rect.fromLTWH(0, 0, mk.width.toDouble(), mk.height.toDouble()),
        full,
        Paint()
          ..colorFilter = _luminanceToAlpha
          ..imageFilter = feather > 0 ? ui.ImageFilter.blur(sigmaX: feather, sigmaY: feather) : null
          ..blendMode = BlendMode.dstIn,
      );
      canvas.restore();

      final pic = rec.endRecording();
      final out = await pic.toImage(w, h);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      base.dispose();
      gen.dispose();
      mk.dispose();
      out.dispose();
      pic.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Turns a white-on-black mask into an alpha channel, so it can drive
  /// BlendMode.dstIn. Rec.709 luminance.
  static const _luminanceToAlpha = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
  ]);

  static Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final f = await codec.getNextFrame();
      codec.dispose();
      return f.image;
    } catch (_) {
      return null;
    }
  }

  static Future<(ui.Image?, ui.Image?)> _decodePair(File a, File b) async =>
      (await _decode(await a.readAsBytes()), await _decode(await b.readAsBytes()));

  /// True when the mask has any painted pixels at all, so an empty mask is
  /// caught before a request is paid for.
  static Future<bool> maskHasContent(File mask) async {
    try {
      final img = await _decode(await mask.readAsBytes());
      if (img == null) return false;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (bd == null) return false;
      final b = bd.buffer.asUint8List();
      for (var i = 0; i < b.length; i += 4 * 97) {
        if (b[i] > 24) return true; // sparse scan: painted areas are white
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
