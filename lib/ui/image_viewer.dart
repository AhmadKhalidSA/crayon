import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Fullscreen image viewer: swipe left/right between images, double-tap to zoom
/// (pinch still works). Used for a single file or a swipeable gallery run.
class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.files, this.initialIndex = 0, this.captions});
  final List<File> files;
  final int initialIndex;
  final List<String>? captions;

  static Future<void> show(BuildContext context, List<File> files,
      {int initialIndex = 0, List<String>? captions}) {
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) =>
          ImageViewer(files: files, initialIndex: initialIndex, captions: captions),
    ));
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.captions != null && _index < widget.captions!.length
        ? widget.captions![_index]
        : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _page,
              itemCount: widget.files.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _ZoomableImage(file: widget.files[i]),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            right: 6,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (widget.files.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${_index + 1} / ${widget.files.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),
          if (caption != null && caption.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: Text(
                caption,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// One image that double-taps to zoom (toward the tapped point) and pinches.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.file});
  final File file;
  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
        ..addListener(() => _tc.value = _animation!.value);
  Animation<Matrix4>? _animation;
  TapDownDetails? _lastTap;

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _tc.value, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    _anim.forward(from: 0);
  }

  void _doubleTap() {
    final zoomed = _tc.value.getMaxScaleOnAxis() > 1.1;
    if (zoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    final pos = _lastTap?.localPosition ?? Offset.zero;
    const scale = 2.8;
    // zoom centred on the tapped point
    final target = Matrix4.identity()
      ..translate(-pos.dx * (scale - 1), -pos.dy * (scale - 1))
      ..scale(scale);
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _lastTap = d,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: Image.file(widget.file, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined, color: T.muted)),
        ),
      ),
    );
  }
}
