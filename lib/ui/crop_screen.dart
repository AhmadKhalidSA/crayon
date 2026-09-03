import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/files.dart';

/// Crop step shown right after an image is picked.
///
/// The image is fitted into a fixed area and a crop rectangle is dragged over
/// it, which keeps the mapping back to source pixels simple and exact. Choosing
/// a preset locks the rectangle's aspect; Free lets it be anything.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.file});
  final File file;

  static Future<File?> open(BuildContext context, File file) =>
      Navigator.of(context).push<File>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropScreen(file: file),
      ));

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _Ratio {
  const _Ratio(this.label, this.w, this.h);
  final String label;
  final double w;
  final double h;
  double? get value => w == 0 ? null : w / h;
}

const _ratios = <_Ratio>[
  _Ratio('Free', 0, 0),
  _Ratio('Original', -1, -1),
  _Ratio('1:1', 1, 1),
  _Ratio('4:5', 4, 5),
  _Ratio('2:3', 2, 3),
  _Ratio('3:4', 3, 4),
  _Ratio('9:16', 9, 16),
  _Ratio('5:4', 5, 4),
  _Ratio('3:2', 3, 2),
  _Ratio('4:3', 4, 3),
  _Ratio('16:9', 16, 9),
  _Ratio('21:9', 21, 9),
];

class _CropScreenState extends State<CropScreen> {
  ui.Image? _img;
  Rect? _crop; // in display coordinates
  Rect _display = Rect.zero;
  int _ratioIndex = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bytes = await widget.file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _img = frame.image);
  }

  double? get _lockedAspect {
    final r = _ratios[_ratioIndex];
    if (r.w == 0) return null; // free
    if (r.w == -1) return _img == null ? null : _img!.width / _img!.height;
    return r.w / r.h;
  }

  /// Places the image inside [box] with BoxFit.contain and returns its rect.
  Rect _fit(Size box) {
    final im = _img!;
    final s = (box.width / im.width) < (box.height / im.height)
        ? box.width / im.width
        : box.height / im.height;
    final w = im.width * s, h = im.height * s;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _resetCrop() {
    final a = _lockedAspect;
    var r = _display.deflate(0);
    if (a != null) {
      var w = r.width, h = w / a;
      if (h > r.height) {
        h = r.height;
        w = h * a;
      }
      r = Rect.fromCenter(center: r.center, width: w, height: h);
    }
    _crop = r;
  }

  Future<void> _apply() async {
    if (_img == null || _crop == null) return;
    setState(() => _busy = true);
    try {
      final im = _img!;
      final scale = im.width / _display.width;
      final src = Rect.fromLTRB(
        ((_crop!.left - _display.left) * scale).clamp(0, im.width.toDouble()),
        ((_crop!.top - _display.top) * scale).clamp(0, im.height.toDouble()),
        ((_crop!.right - _display.left) * scale).clamp(0, im.width.toDouble()),
        ((_crop!.bottom - _display.top) * scale).clamp(0, im.height.toDouble()),
      );
      final w = src.width.round().clamp(1, im.width);
      final h = src.height.round().clamp(1, im.height);

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImageRect(im, src, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..filterQuality = FilterQuality.high);
      final pic = rec.endRecording();
      final out = await pic.toImage(w, h);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      pic.dispose();
      out.dispose();
      if (bd == null) throw Exception('encode failed');
      final f = await Files.writeRefBytes(bd.buffer.asUint8List(), 'png');
      if (mounted) Navigator.pop(context, f);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not crop that image')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Crop'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, widget.file),
            child: const Text('Skip', style: TextStyle(color: T.muted, fontSize: 14)),
          ),
        ],
      ),
      body: _img == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: T.muted))
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(builder: (_, c) {
                      final box = Size(c.maxWidth, c.maxHeight);
                      final fitted = _fit(box);
                      if (_display != fitted) {
                        _display = fitted;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(_resetCrop);
                        });
                      }
                      _crop ??= fitted;
                      return _CropOverlay(
                        image: _img!,
                        display: _display,
                        crop: _crop!,
                        aspect: _lockedAspect,
                        onChange: (r) => setState(() => _crop = r),
                      );
                    }),
                  ),
                ),
                _ratioBar(),
                _footer(),
              ],
            ),
    );
  }

  Widget _ratioBar() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: T.pad),
        itemCount: _ratios.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = _ratios[i];
          final sel = i == _ratioIndex;
          // the shape preview: the box drawn at this ratio
          double w = 24, h = 24;
          if (r.w > 0) {
            final a = r.w / r.h;
            if (a >= 1) {
              h = 24 / a;
            } else {
              w = 24 * a;
            }
          }
          return GestureDetector(
            onTap: () => setState(() {
              _ratioIndex = i;
              _resetCrop();
            }),
            child: Container(
              width: 62,
              decoration: BoxDecoration(
                color: sel ? T.surfaceHi : T.surface,
                borderRadius: BorderRadius.circular(T.rTight),
                border: Border.all(color: sel ? T.ink : T.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 26,
                    child: Center(
                      child: r.w == 0
                          ? Icon(Icons.crop_free_rounded, size: 18, color: sel ? T.ink : T.muted)
                          : r.w == -1
                              ? Icon(Icons.image_outlined, size: 18, color: sel ? T.ink : T.muted)
                              : Container(
                                  width: w,
                                  height: h,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: sel ? T.ink : T.muted, width: 1.4),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(r.label,
                      style: TextStyle(
                          fontSize: 9.5,
                          color: sel ? T.ink : T.muted,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _footer() {
    final im = _img;
    final scale = im == null || _display.width == 0 ? 1.0 : im.width / _display.width;
    final w = _crop == null ? 0 : (_crop!.width * scale).round();
    final h = _crop == null ? 0 : (_crop!.height * scale).round();
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: T.border))),
      padding: const EdgeInsets.fromLTRB(T.pad, 12, T.pad, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$w x $h',
                    style: const TextStyle(color: T.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                const Text('output size', style: TextStyle(color: T.faint, fontSize: 10.5)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PrimaryButton(
                label: 'Use image',
                icon: Icons.check_rounded,
                busy: _busy,
                onTap: _busy ? null : _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the image, dims outside the crop, and handles corner / body drags.
class _CropOverlay extends StatefulWidget {
  const _CropOverlay({
    required this.image,
    required this.display,
    required this.crop,
    required this.aspect,
    required this.onChange,
  });
  final ui.Image image;
  final Rect display;
  final Rect crop;
  final double? aspect;
  final ValueChanged<Rect> onChange;

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  static const _handle = 30.0;
  int _grab = -1; // 0..3 corners, 4 = whole rect
  late Rect _start;
  late Offset _startPos;

  int _hitTest(Offset p) {
    final c = widget.crop;
    final corners = [c.topLeft, c.topRight, c.bottomLeft, c.bottomRight];
    for (var i = 0; i < 4; i++) {
      if ((p - corners[i]).distance < _handle) return i;
    }
    return c.contains(p) ? 4 : -1;
  }

  void _drag(Offset delta) {
    final d = widget.display;
    var r = _start;
    const minSize = 40.0;

    if (_grab == 4) {
      r = r.shift(delta);
      // keep inside the image
      var dx = 0.0, dy = 0.0;
      if (r.left < d.left) dx = d.left - r.left;
      if (r.right > d.right) dx = d.right - r.right;
      if (r.top < d.top) dy = d.top - r.top;
      if (r.bottom > d.bottom) dy = d.bottom - r.bottom;
      widget.onChange(r.shift(Offset(dx, dy)));
      return;
    }

    var l = r.left, t = r.top, rt = r.right, b = r.bottom;
    switch (_grab) {
      case 0:
        l += delta.dx;
        t += delta.dy;
        break;
      case 1:
        rt += delta.dx;
        t += delta.dy;
        break;
      case 2:
        l += delta.dx;
        b += delta.dy;
        break;
      case 3:
        rt += delta.dx;
        b += delta.dy;
        break;
    }
    l = l.clamp(d.left, d.right - minSize);
    rt = rt.clamp(d.left + minSize, d.right);
    t = t.clamp(d.top, d.bottom - minSize);
    b = b.clamp(d.top + minSize, d.bottom);
    var out = Rect.fromLTRB(l, t, rt, b);

    final a = widget.aspect;
    if (a != null) {
      // hold the aspect by adjusting the edge that moved least
      var w = out.width, h = out.height;
      if (w / h > a) {
        w = h * a;
      } else {
        h = w / a;
      }
      final anchor = switch (_grab) {
        0 => out.bottomRight,
        1 => out.bottomLeft,
        2 => out.topRight,
        _ => out.topLeft,
      };
      out = switch (_grab) {
        0 => Rect.fromLTRB(anchor.dx - w, anchor.dy - h, anchor.dx, anchor.dy),
        1 => Rect.fromLTRB(anchor.dx, anchor.dy - h, anchor.dx + w, anchor.dy),
        2 => Rect.fromLTRB(anchor.dx - w, anchor.dy, anchor.dx, anchor.dy + h),
        _ => Rect.fromLTRB(anchor.dx, anchor.dy, anchor.dx + w, anchor.dy + h),
      };
      if (!d.contains(out.topLeft) || !d.contains(out.bottomRight)) return;
    }
    widget.onChange(out);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (e) {
        _grab = _hitTest(e.localPosition);
        _start = widget.crop;
        _startPos = e.localPosition;
      },
      onPanUpdate: (e) {
        if (_grab < 0) return;
        _drag(e.localPosition - _startPos);
      },
      onPanEnd: (_) => _grab = -1,
      child: CustomPaint(
        size: Size.infinite,
        painter: _CropPainter(widget.image, widget.display, widget.crop),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.display, this.crop);
  final ui.Image image;
  final Rect display;
  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      display,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // dim everything outside the crop
    final dim = Paint()..color = const Color(0xCC000000);
    canvas.save();
    canvas.clipRect(crop, clipOp: ui.ClipOp.difference);
    canvas.drawRect(display, dim);
    canvas.restore();

    final line = Paint()
      ..color = T.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(crop, line);

    // thirds
    final thin = Paint()
      ..color = T.ink.withValues(alpha: 0.28)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), thin);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), thin);
    }

    // corner handles: an L at each corner, drawn inside the crop rect
    final h = Paint()..color = T.ink;
    const len = 20.0, thick = 3.0;
    final c = crop;
    // top left
    canvas.drawRect(Rect.fromLTWH(c.left, c.top, len, thick), h);
    canvas.drawRect(Rect.fromLTWH(c.left, c.top, thick, len), h);
    // top right
    canvas.drawRect(Rect.fromLTWH(c.right - len, c.top, len, thick), h);
    canvas.drawRect(Rect.fromLTWH(c.right - thick, c.top, thick, len), h);
    // bottom left
    canvas.drawRect(Rect.fromLTWH(c.left, c.bottom - thick, len, thick), h);
    canvas.drawRect(Rect.fromLTWH(c.left, c.bottom - len, thick, len), h);
    // bottom right
    canvas.drawRect(Rect.fromLTWH(c.right - len, c.bottom - thick, len, thick), h);
    canvas.drawRect(Rect.fromLTWH(c.right - thick, c.bottom - len, thick, len), h);
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.crop != crop || old.display != display || old.image != image;
}
