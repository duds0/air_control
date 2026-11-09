import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/temp_step.dart';

export '../../domain/temp_step.dart' show formatTemp;

/// A 270° draggable arc dial for the target temperature.
class TemperatureDial extends StatelessWidget {
  const TemperatureDial({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.accent,
    required this.onChanged,
    required this.enabled,
    this.currentTemp,
    this.centerLabel,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final Color accent;
  final bool enabled;
  final double? currentTemp;
  final String? centerLabel; // overrides the big number (e.g. "—")
  final ValueChanged<double> onChanged;

  static const _start = 3 * math.pi / 4;
  static const _sweep = 3 * math.pi / 2;

  double _fromOffset(Offset p, Size size) {
    final c = size.center(Offset.zero);
    var a = math.atan2(p.dy - c.dy, p.dx - c.dx);
    if (a < 0) a += 2 * math.pi;
    var rel = (a - _start) % (2 * math.pi);
    if (rel > _sweep) {
      rel = rel > _sweep + (2 * math.pi - _sweep) / 2 ? 0 : _sweep;
    }
    final raw = min + (rel / _sweep) * (max - min);
    final snapped = (raw / step).round() * step;
    return snapped.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final frac = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        void handle(Offset p) {
          if (!enabled) return;
          final v = _fromOffset(p, size);
          if (v != value) {
            HapticFeedback.selectionClick();
            onChanged(v);
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          onTapDown: (d) => handle(d.localPosition),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: frac, end: frac),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) => CustomPaint(
              painter: _DialPainter(
                fraction: f,
                accent: accent,
                track: onSurface.withValues(alpha: 0.10),
                // Bright knob in both themes so it stands out from the track.
                knob: theme.brightness == Brightness.dark
                    ? const Color(0xFFF2F4F7)
                    : theme.colorScheme.surface,
                showKnob: enabled,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        centerLabel ?? formatTemp(value),
                        key: ValueKey(centerLabel ?? value),
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontSize: box.maxWidth * 0.26,
                          fontWeight: FontWeight.w300,
                          height: 1,
                          letterSpacing: -2,
                          color: onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentTemp == null
                          ? ' '
                          : 'Ambiente ${formatTemp(currentTemp!)}°',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface.withValues(alpha: 0.55),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.fraction,
    required this.accent,
    required this.track,
    required this.knob,
    required this.showKnob,
  });

  final double fraction;
  final Color accent;
  final Color track;
  final Color knob;
  final bool showKnob;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final radius = (size.width - stroke) / 2 - size.width * 0.03;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: radius);
    const start = TemperatureDial._start;
    const sweep = TemperatureDial._sweep;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, start, sweep, false, trackPaint);

    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = accent;
    if (fraction > 0) {
      canvas.drawArc(rect, start, sweep * fraction, false, active);
    }

    if (showKnob) {
      final a = start + sweep * fraction;
      final p = c + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawCircle(
        p + const Offset(0, 2),
        stroke * 0.62,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(p, stroke * 0.62, Paint()..color = knob);
      canvas.drawCircle(p, stroke * 0.26, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_DialPainter o) =>
      o.fraction != fraction ||
      o.accent != accent ||
      o.track != track ||
      o.knob != knob ||
      o.showKnob != showKnob;
}
