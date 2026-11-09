import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/energy.dart';
import '../../domain/energy_controller.dart';
import 'controls.dart';

/// Bottom sheet with today's usage and a daily bar chart (7 / 14 / 30 days).
Future<void> showEnergySheet(BuildContext context, {required Color accent}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _EnergySheet(accent: accent),
  );
}

class _EnergySheet extends ConsumerStatefulWidget {
  const _EnergySheet({required this.accent});
  final Color accent;

  @override
  ConsumerState<_EnergySheet> createState() => _EnergySheetState();
}

class _EnergySheetState extends ConsumerState<_EnergySheet> {
  int _range = 14;
  int? _selected; // index within the visible days; null = the last (today)

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final all = ref.watch(energyControllerProvider.select((s) => s.days));
    final visible =
        all.length > _range ? all.sublist(all.length - _range) : all;

    final sel = visible.isEmpty
        ? null
        : (_selected ?? visible.length - 1).clamp(0, visible.length - 1);
    final picked = sel == null ? null : visible[sel];
    final isToday = picked != null && picked.isSameDay(DateTime.now());

    final total = visible.fold<double>(0, (a, d) => a + d.wh);
    final avg = visible.isEmpty ? 0.0 : total / visible.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Consumo de energia',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (picked == null)
              Text('Sem dados de consumo ainda.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: onSurface.withValues(alpha: 0.6)))
            else ...[
              Text(
                isToday ? 'Hoje, até agora' : formatDayMonth(picked.date),
                style: theme.textTheme.labelLarge?.copyWith(
                    color: onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 2),
              Text(
                formatKwh(picked.wh),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w300,
                  color: widget.accent,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 150,
                child: _BarChart(
                  days: visible,
                  selected: sel!,
                  accent: widget.accent,
                  labelColor: onSurface.withValues(alpha: 0.55),
                  onSelect: (i) => setState(() => _selected = i),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _Stat('Média por dia', formatKwh(avg))),
                  Expanded(
                    child: _Stat('Total em ${visible.length} dias',
                        formatKwh(total)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 260,
                  child: PillSelector<int>(
                    compact: true,
                    options: const [
                      PillOption(7, '7 dias'),
                      PillOption(14, '14 dias'),
                      PillOption(30, '30 dias'),
                    ],
                    selected: _range,
                    accent: widget.accent,
                    onSelected: (v) => setState(() {
                      _range = v;
                      _selected = null;
                    }),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.days,
    required this.selected,
    required this.accent,
    required this.labelColor,
    required this.onSelect,
  });

  final List<EnergyDay> days;
  final int selected;
  final Color accent;
  final Color labelColor;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      void pick(Offset p) {
        final i = (p.dx / box.maxWidth * days.length).floor();
        onSelect(i.clamp(0, days.length - 1));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => pick(d.localPosition),
        onHorizontalDragUpdate: (d) => pick(d.localPosition),
        child: CustomPaint(
          size: Size(box.maxWidth, box.maxHeight),
          painter: _BarPainter(days, selected, accent, labelColor),
        ),
      );
    });
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.days, this.selected, this.accent, this.labelColor);

  final List<EnergyDay> days;
  final int selected;
  final Color accent;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const labelH = 18.0;
    final chartH = size.height - labelH;
    final maxV = days.map((d) => d.wh).reduce((a, b) => a > b ? a : b);
    final top = maxV <= 0 ? 1.0 : maxV;

    final n = days.length;
    final gap = n > 20 ? 3.0 : 5.0;
    final barW = (size.width - gap * (n - 1)) / n;
    // Label every bar for a week, every few for longer ranges.
    final every = n <= 8 ? 1 : (n <= 16 ? 2 : 5);

    for (var i = 0; i < n; i++) {
      final x = i * (barW + gap);
      final h = (days[i].wh / top * chartH).clamp(2.0, chartH);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chartH - h, barW, h),
        Radius.circular((barW / 2).clamp(0, 6)),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = i == selected ? accent : accent.withValues(alpha: 0.30),
      );

      final isLast = i == n - 1;
      if (i % every == 0 || isLast) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${days[i].date.day}',
            style: TextStyle(
              fontSize: 10,
              color: i == selected ? accent : labelColor,
              fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, chartH + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.days != days || o.selected != selected || o.accent != accent;
}
