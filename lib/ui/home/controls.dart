import 'package:flutter/material.dart';

class PillOption<T> {
  const PillOption(this.value, this.label, [this.icon]);
  final T value;
  final String label;
  final IconData? icon;
}

/// Minimal segmented selector with a sliding highlight.
class PillSelector<T> extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.accent,
    required this.onSelected,
    this.compact = false,
  });

  final bool compact;
  final List<PillOption<T>> options;
  final T? selected;
  final Color accent;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final index = options.indexWhere((o) => o.value == selected);
    final dark = theme.brightness == Brightness.dark;

    return Container(
      height: compact ? 40 : 52,
      padding: EdgeInsets.all(compact ? 3 : 4),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(compact ? 20 : 26),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / options.length;
        return Stack(
          children: [
            if (index >= 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: w * index,
                width: w,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    // Light: white chip on the soft track. Dark: a lighter
                    // chip (a darker one would vanish into the background).
                    color: dark
                        ? onSurface.withValues(alpha: 0.16)
                        : theme.colorScheme.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: dark
                        ? const []
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                ),
              ),
            Row(
              children: [
                for (final o in options)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => onSelected(o.value),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: theme.textTheme.labelLarge!.copyWith(
                            fontWeight: o.value == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: o.value == selected
                                ? accent
                                : onSurface.withValues(alpha: 0.6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (o.icon != null) ...[
                                Icon(o.icon, size: 18),
                                const SizedBox(width: 6),
                              ],
                              Text(o.label),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// Small rounded toggle tile (swing, display light, timer...).
class ToggleTile extends StatelessWidget {
  const ToggleTile({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  /// Disabled tiles are dimmed and ignore taps.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Expanded(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: enabled ? 1 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: _tile(theme, onSurface),
        ),
      ),
    );
  }

  Widget _tile(ThemeData theme, Color onSurface) {
    return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: 76,
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.16)
                : onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 24,
                  color: active ? accent : onSurface.withValues(alpha: 0.65)),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: active ? accent : onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class PowerButton extends StatelessWidget {
  const PowerButton({
    super.key,
    required this.on,
    required this.accent,
    required this.onTap,
  });

  final bool on;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? accent : onSurface.withValues(alpha: 0.08),
          // A soft, tight glow: negative spread keeps it hugging the button so
          // it never reaches the controls above and below.
          boxShadow: on
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.32),
                    blurRadius: 22,
                    spreadRadius: -6,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Icon(
          Icons.power_settings_new_rounded,
          size: 32,
          color: on ? Colors.white : onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
