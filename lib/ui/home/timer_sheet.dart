import 'package:flutter/material.dart';

/// Bottom sheet to set or cancel the "desligar em..." (sleep) timer.
Future<void> showSleepTimerSheet(
  BuildContext context, {
  required bool active,
  required Color accent,
  required ValueChanged<Duration> onSet,
  required VoidCallback onCancel,
}) {
  const options = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 4),
    Duration(hours: 6),
    Duration(hours: 8),
  ];

  String label(Duration d) =>
      d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h';

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Desligar em',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final d in options)
                  ActionChip(
                    label: Text(label(d)),
                    side: BorderSide.none,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                        color: accent, fontWeight: FontWeight.w600),
                    onPressed: () {
                      onSet(d);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () {
                  onCancel();
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.timer_off_outlined),
                label: const Text('Cancelar timer'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
