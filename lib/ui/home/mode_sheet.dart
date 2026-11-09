import 'package:flutter/material.dart';

class ModeInfo {
  const ModeInfo(this.label, this.icon, this.hint);
  final String label;
  final IconData icon;
  final String hint;

  static const known = {
    'COOL': ModeInfo('Frio', Icons.ac_unit_rounded, 'Resfria o ambiente'),
    'FAN': ModeInfo('Ventilar', Icons.air_rounded, 'Só circula o ar, sem resfriar'),
    'AIR_DRY': ModeInfo('Seco', Icons.water_drop_outlined, 'Reduz a umidade do ar'),
  };

  static ModeInfo of(String mode) =>
      known[mode] ?? ModeInfo(mode, Icons.tune_rounded, '');
}

/// Single button showing the current mode. Changing it takes two deliberate
/// steps (open the sheet, pick a mode), so it can't be changed by accident.
class ModeButton extends StatelessWidget {
  const ModeButton({
    super.key,
    required this.mode,
    required this.accent,
    required this.onTap,
  });

  final String mode;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final info = ModeInfo.of(mode);
    return Material(
      color: onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(Icons.tune_rounded,
                    size: 20, color: onSurface.withValues(alpha: 0.65)),
                const SizedBox(width: 10),
                Text('Modos',
                    style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.8))),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    key: ValueKey(mode),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(info.icon, size: 18, color: accent),
                      const SizedBox(width: 6),
                      Text(info.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700, color: accent)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.keyboard_arrow_up_rounded,
                    size: 20, color: onSurface.withValues(alpha: 0.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing the available modes. Picking one applies it and closes.
Future<void> showModeSheet(
  BuildContext context, {
  required List<String> modes,
  required String current,
  required Color accent,
  required ValueChanged<String> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final onSurface = theme.colorScheme.onSurface;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modos',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              for (final m in modes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ModeTile(
                    info: ModeInfo.of(m),
                    selected: m == current,
                    accent: accent,
                    onSurface: onSurface,
                    onTap: () {
                      if (m != current) onSelected(m);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.info,
    required this.selected,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final ModeInfo info;
  final bool selected;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.14)
          : onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(info.icon,
                  size: 26,
                  color: selected ? accent : onSurface.withValues(alpha: 0.7)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selected ? accent : onSurface)),
                    if (info.hint.isNotEmpty)
                      Text(info.hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
