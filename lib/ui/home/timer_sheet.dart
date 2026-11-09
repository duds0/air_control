import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../domain/ac_controller.dart';

/// Bottom sheet with every timer the unit supports:
///  * "Ligar às"    — turn on at a fixed time
///  * "Desligar às" — turn off at a fixed time
///  * "Desligar em" — turn off after 30 min / N hours
/// It watches the live state, so it reflects changes while it is open.
Future<void> showTimerSheet(BuildContext context, {required Color accent}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _TimerSheet(accent: accent),
  );
}

/// Durations the unit accepts for "turn off in" (verified: 30 min and whole
/// hours; 1h30, 2h30 and 15 min are rejected).
const _sleepOptions = [
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 3),
  Duration(hours: 4),
  Duration(hours: 6),
  Duration(hours: 8),
];

String _durationLabel(Duration d) =>
    d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h';

class _TimerSheet extends ConsumerWidget {
  const _TimerSheet({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ac = ref.watch(acControllerProvider.select((s) => s.ac));
    final p = ref.watch(acControllerProvider.select((s) => s.profile));
    final ctrl = ref.read(acControllerProvider.notifier);
    final theme = Theme.of(context);
    if (ac == null) return const SizedBox(height: 120);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Timers',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (p.canStartTimer) ...[
              _ClockRow(
                icon: Icons.alarm_on_rounded,
                label: 'Ligar às',
                time: ac.startAt,
                accent: accent,
                onPick: ctrl.setStartTimer,
                onCancel: ctrl.cancelStartTimer,
              ),
              const SizedBox(height: 10),
            ],
            if (p.canStopTimer) ...[
              _ClockRow(
                icon: Icons.alarm_off_rounded,
                label: 'Desligar às',
                time: ac.stopAt,
                accent: accent,
                onPick: ctrl.setStopTimer,
                onCancel: ctrl.cancelStopTimer,
              ),
              const SizedBox(height: 10),
            ],
            if (p.canSleepTimer) ...[
              const SizedBox(height: 10),
              Text('Desligar em',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6))),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final d in _sleepOptions)
                    ChoiceChip(
                      label: Text(_durationLabel(d)),
                      selected: ac.sleepFor == d,
                      showCheckmark: false,
                      side: BorderSide.none,
                      backgroundColor: accent.withValues(alpha: 0.10),
                      selectedColor: accent,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: ac.sleepFor == d ? Colors.white : accent,
                      ),
                      onSelected: (_) {
                        ctrl.setSleepTimer(d);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
              if (ac.sleepTimerSet) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    ctrl.cancelSleepTimer();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.timer_off_outlined),
                  label: const Text('Cancelar timer'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// One "turn on/off at HH:MM" row: tap to pick a time, ✕ to cancel.
class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.icon,
    required this.label,
    required this.time,
    required this.accent,
    required this.onPick,
    required this.onCancel,
  });

  final IconData icon;
  final String label;
  final ClockTime? time;
  final Color accent;
  final ValueChanged<ClockTime> onPick;
  final VoidCallback onCancel;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now().add(const Duration(hours: 1));
    final initial = time == null
        ? TimeOfDay(hour: now.hour, minute: 0)
        : TimeOfDay(hour: time!.hour, minute: time!.minute);
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: label,
      builder: (context, child) => MediaQuery(
        // The unit's timers are 24 h clock times.
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) onPick(ClockTime(t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final active = time != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        color: active
            ? accent.withValues(alpha: 0.14)
            : onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? accent.withValues(alpha: 0.45) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _pick(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(
                  children: [
                    Icon(icon,
                        color: active ? accent : onSurface.withValues(alpha: 0.65)),
                    const SizedBox(width: 14),
                    Text(label,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      active ? time!.label : 'Definir',
                      style: active
                          ? theme.textTheme.titleLarge?.copyWith(
                              color: accent, fontWeight: FontWeight.w700)
                          : theme.textTheme.bodyMedium?.copyWith(
                              color: onSurface.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (active)
            IconButton(
              tooltip: 'Cancelar',
              icon: Icon(Icons.close_rounded,
                  color: onSurface.withValues(alpha: 0.7)),
              onPressed: onCancel,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
