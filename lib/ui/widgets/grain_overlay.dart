import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A near-invisible film grain painted over the whole screen.
///
/// Dark, low-contrast gradients can't be shown smoothly with 8 bits per
/// channel: the screen reproduces them as visible bands ("stripes"). Adding
/// ~1–2 levels of per-pixel noise (dithering) makes neighbouring bands blend
/// into each other, so the gradient and soft glows look continuous.
class GrainOverlay extends StatefulWidget {
  const GrainOverlay({super.key, required this.dark});

  /// Dark themes lighten pixels slightly, light themes darken them slightly.
  final bool dark;

  @override
  State<GrainOverlay> createState() => _GrainOverlayState();
}

class _GrainOverlayState extends State<GrainOverlay> {
  static const _tile = 128;
  static const _maxAlpha = 5; // out of 255: only a few brightness levels

  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(GrainOverlay old) {
    super.didUpdateWidget(old);
    if (old.dark != widget.dark) _build();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _build() {
    final dark = widget.dark;
    final rnd = Random(7); // fixed seed: identical grain every launch
    final px = Uint8List(_tile * _tile * 4);
    for (var i = 0; i < _tile * _tile; i++) {
      final a = rnd.nextInt(_maxAlpha + 1);
      final c = dark ? a : 0; // premultiplied: white (dark theme) or black
      px[i * 4] = c;
      px[i * 4 + 1] = c;
      px[i * 4 + 2] = c;
      px[i * 4 + 3] = a;
    }
    ui.decodeImageFromPixels(px, _tile, _tile, ui.PixelFormat.rgba8888, (img) {
      if (!mounted || dark != widget.dark) {
        img.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = img;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _GrainPainter(image, MediaQuery.devicePixelRatioOf(context)),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.image, this.dpr);

  final ui.Image image;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    // One grain pixel = one physical pixel, so dithering works per pixel.
    final m = Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1).storage;
    final shader = ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      m,
      filterQuality: FilterQuality.none,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.image != image || old.dpr != dpr;
}
