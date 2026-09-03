import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/files.dart';

/// What the brush is for.
enum BrushMode {
  /// Paint opaque marks INTO the picture, flattened into the file. Used to
  /// block out faces, logos or anything the model should not see.
  block,

  /// Paint a region to be regenerated. Nothing is burned into the picture: the
  /// strokes come back as a separate mask for the inpaint pipeline.
  mask,
}

class BrushResult {
  BrushResult({this.image, this.mask});

  /// block mode: the flattened image
  final File? image;

  /// mask mode: white-on-black mask at the source image's exact size
  final File? mask;
}

class _Stroke {
  _Stroke(this.color, this.width, this.erase);
  final Color color;
  final double width;
  final bool erase;
  final List<Offset> points = [];
}

/// Paint over an image, either to hide parts of it or to mark a region.
class BrushScreen extends StatefulWidget {
  const BrushScreen({super.key, required this.file, required this.mode});
  final File file;
  final BrushMode mode;

  static Future<BrushResult?> open(BuildContext context, File file, BrushMode mode) =>
      Navigator.of(context).push<BrushResult>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BrushScreen(file: file, mode: mode),
      ));

  @override
  State<BrushScreen> createState() => _BrushScreenState();
}

class _BrushScreenState extends State<BrushScreen> {
  ui.Image? _img;
  Rect _display = Rect.zero;
  final List<_Stroke> _strokes = [];
  final List<_Stroke> _redo = [];

  double _size = 40;
  double _opacity = 1.0;
  bool _erasing = false;
  int _colorIndex = 0;
  bool _busy = false;

  static const _colors = [
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFF808080),
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
  ];

  bool get _isMask => widget.mode == BrushMode.mask;
  Color get _color => _isMask ? const Color(0xFFFF00FF) : _colors[_colorIndex];

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

  Rect _fit(Size box) {
    final im = _img!;
    final s = (box.width / im.width) < (box.height / im.height)
        ? box.width / im.width
        : box.height / im.height;
    final w = im.width * s, h = im.height * s;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _start(Offset p) {
    _redo.clear();
    final st = _Stroke(_color.withValues(alpha: _isMask ? 1.0 : _opacity), _size, _erasing);
    st.points.add(p);
    setState(() => _strokes.add(st));
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.points.add(p));
  }

  Future<void> _apply() async {
    if (_img == null || _strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    try {
      final im = _img!;
      final scale = im.width / _display.width;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final full = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());

      if (_isMask) {
        // mask output: white where painted, black elsewhere
        canvas.drawRect(full, Paint()..color = const Color(0xFF000000));
      } else {
        canvas.drawImageRect(im, full, full, Paint()..filterQuality = FilterQuality.high);
      }

      // strokes are stored in display space, so map them into image space
      canvas.saveLayer(full, Paint());
      for (final st in _strokes) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = st.width * scale
          ..color = _isMask ? const Color(0xFFFFFFFF) : st.color
          ..blendMode = st.erase ? BlendMode.clear : BlendMode.srcOver;
        final path = Path();
        for (var i = 0; i < st.points.length; i++) {
          final p = (st.points[i] - _display.topLeft) * scale;
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
            // a tap with no drag should still leave a dot
            if (st.points.length == 1) path.lineTo(p.dx + 0.1, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
      canvas.restore();

      final pic = rec.endRecording();
      final out = await pic.toImage(im.width, im.height);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      pic.dispose();
      out.dispose();
      if (bd == null) throw Exception('encode failed');
      final f = await Files.writeRefBytes(bd.buffer.asUint8List(), 'png');
      if (!mounted) return;
      Navigator.pop(context, _isMask ? BrushResult(mask: f) : BrushResult(image: f));
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not apply those strokes')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(_isMask ? 'Mark the area to change' : 'Draw on image'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 20),
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _redo.add(_strokes.removeLast())),
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded, size: 20),
            onPressed: _redo.isEmpty ? null : () => setState(() => _strokes.add(_redo.removeLast())),
          ),
          IconButton(
            icon: const Icon(Icons.layers_clear_rounded, size: 20),
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() {
                      _strokes.clear();
                      _redo.clear();
                    }),
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
                      _display = _fit(Size(c.maxWidth, c.maxHeight));
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (e) => _start(e.localPosition),
                        onPanUpdate: (e) => _extend(e.localPosition),
                        onTapDown: (e) => _start(e.localPosition),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _BrushPainter(_img!, _display, _strokes, _isMask),
                        ),
                      );
                    }),
                  ),
                ),
                _tools(),
                _footer(),
              ],
            ),
    );
  }

  Widget _tools() {
    return Container(
      padding: const EdgeInsets.fromLTRB(T.pad, 10, T.pad, 6),
      decoration: const BoxDecoration(
        color: T.surface,
        border: Border(top: BorderSide(color: T.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_erasing ? Icons.auto_fix_normal_rounded : Icons.brush_rounded, size: 16, color: T.ink),
              const SizedBox(width: 10),
              const Text('Size', style: TextStyle(color: T.muted, fontSize: 12)),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    activeTrackColor: T.ink,
                    inactiveTrackColor: T.border,
                    thumbColor: T.ink,
                    overlayColor: T.ink.withValues(alpha: 0.1),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: _size,
                    min: 6,
                    max: 140,
                    onChanged: (v) => setState(() => _size = v),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text('${_size.round()}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: T.ink, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (!_isMask)
            Row(
              children: [
                const SizedBox(width: 26),
                const Text('Opacity', style: TextStyle(color: T.muted, fontSize: 12)),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      activeTrackColor: T.ink,
                      inactiveTrackColor: T.border,
                      thumbColor: T.ink,
                      overlayColor: T.ink.withValues(alpha: 0.1),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _opacity,
                      min: 0.1,
                      max: 1.0,
                      onChanged: (v) => setState(() => _opacity = v),
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text('${(_opacity * 100).round()}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: T.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (!_isMask) ...[
                for (var i = 0; i < _colors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() {
                      _colorIndex = i;
                      _erasing = false;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _colors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (!_erasing && _colorIndex == i) ? T.ink : T.border,
                          width: (!_erasing && _colorIndex == i) ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
              ] else
                const Expanded(
                  child: Text('Paint over what should be regenerated',
                      style: TextStyle(color: T.faint, fontSize: 11.5)),
                ),
              GestureDetector(
                onTap: () => setState(() => _erasing = !_erasing),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _erasing ? T.ink : T.bg,
                    borderRadius: BorderRadius.circular(T.rPill),
                    border: Border.all(color: _erasing ? T.ink : T.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_fix_normal_rounded, size: 14, color: _erasing ? T.bg : T.ink),
                      const SizedBox(width: 6),
                      Text('Erase',
                          style: TextStyle(
                              color: _erasing ? T.bg : T.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: T.border))),
      padding: const EdgeInsets.fromLTRB(T.pad, 12, T.pad, 12),
      child: SafeArea(
        top: false,
        child: PrimaryButton(
          label: _isMask ? 'Use this area' : 'Apply',
          icon: Icons.check_rounded,
          busy: _busy,
          onTap: _busy ? null : _apply,
        ),
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  _BrushPainter(this.image, this.display, this.strokes, this.isMask);
  final ui.Image image;
  final Rect display;
  final List<_Stroke> strokes;
  final bool isMask;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      display,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.saveLayer(display, Paint());
    for (final st in strokes) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = st.width
        ..color = isMask ? const Color(0x99FF00FF) : st.color
        ..blendMode = st.erase ? BlendMode.clear : BlendMode.srcOver;
      final path = Path();
      for (var i = 0; i < st.points.length; i++) {
        final p = st.points[i];
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
          if (st.points.length == 1) path.lineTo(p.dx + 0.1, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrushPainter old) => true;
}
