import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../domain/ac_controller.dart';
import '../../domain/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/grain_overlay.dart';
import 'controls.dart';
import 'mode_sheet.dart';
import 'temperature_dial.dart';
import 'timer_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = ref.read(acControllerProvider.notifier);
    if (s == AppLifecycleState.resumed) {
      c.resume();
    } else {
      c.pause();
    }
  }

  static const _windLabels = {
    'AUTO': 'Auto',
    'LOW': 'Baixo',
    'MID': 'Médio',
    'HIGH': 'Alto',
  };

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(acControllerProvider);
    final ctrl = ref.read(acControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final ac = view.ac;
    final palette = ModePalette.of(ac?.mode ?? 'COOL', ac?.power ?? false, brightness);

    ref.listen(acControllerProvider.select((s) => s.notice), (_, n) {
      if (n == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(n.text)));
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.top, palette.bottom],
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  children: [
                    _TopBar(view: view, palette: palette),
                    Expanded(
                      child: view.fatal != null
                          ? _Message(
                              text: view.fatal!,
                              onRetry: ctrl.retry,
                            )
                          : ac == null
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: palette.accent,
                                    strokeWidth: 2,
                                  ),
                                )
                              : _Body(view: view, ac: ac, palette: palette),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Over everything, so the gradient *and* the power-button glow are
        // dithered (no banding).
        GrainOverlay(dark: brightness == Brightness.dark),
      ],
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.view, required this.palette});

  final AcViewState view;
  final ModePalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.device?.alias ?? 'Air Control',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: view.offline
                      ? InkWell(
                          key: const ValueKey('off'),
                          onTap: ref.read(acControllerProvider.notifier).retry,
                          child: Text('Sem conexão · tocar para tentar',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.orange.shade700)),
                        )
                      : view.ac?.hasError == true
                          ? Text('Aparelho reportou erro',
                              key: const ValueKey('err'),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.red.shade400))
                          : const SizedBox(key: ValueKey('ok'), height: 16),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isDark ? 'Modo claro' : 'Modo escuro',
            onPressed: () =>
                ref.read(themeModeProvider.notifier).toggle(brightness),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                key: ValueKey(isDark),
                color: onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded,
                color: onSurface.withValues(alpha: 0.7)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (v) {
              if (v == 'out') ref.read(credentialsProvider.notifier).signOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'out', child: Text('Desconectar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.view, required this.ac, required this.palette});

  final AcViewState view;
  final AcState ac;
  final ModePalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(acControllerProvider.notifier);
    final p = view.profile;
    final accent = palette.accent;
    final tempEditable = ac.power && ac.mode == 'COOL';
    final step = ref.watch(effectiveTempStepProvider);
    final stepOptions = ref.watch(tempStepOptionsProvider);

    final dial = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: tempEditable ? 1 : 0.45,
              child: TemperatureDial(
                value: ac.targetTemp,
                min: p.minTemp,
                max: p.maxTemp,
                step: step,
                accent: accent,
                enabled: tempEditable,
                currentTemp: ac.currentTemp,
                centerLabel: !ac.power
                    ? 'Off'
                    : ac.mode == 'COOL'
                        ? null
                        : (ac.currentTemp != null
                            ? formatTemp(ac.currentTemp!)
                            : '—'),
                onChanged: ctrl.setTargetTemp,
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: tempEditable ? 1 : 0,
            child: IgnorePointer(
              ignoring: !tempEditable,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundIcon(Icons.remove_rounded, () => ctrl.nudgeTemp(-1)),
                  if (stepOptions.length > 1) ...[
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 130,
                      child: PillSelector<double>(
                        compact: true,
                        options: [
                          for (final s in stepOptions)
                            PillOption(s, '${formatTemp(s)}°'),
                        ],
                        selected: step,
                        accent: accent,
                        onSelected: ref.read(tempStepProvider.notifier).set,
                      ),
                    ),
                    const SizedBox(width: 14),
                  ] else
                    const SizedBox(width: 28),
                  _RoundIcon(Icons.add_rounded, () => ctrl.nudgeTemp(1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final controls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: PowerButton(
              on: ac.power,
              accent: accent,
              onTap: ctrl.togglePower,
            ),
          ),
          const SizedBox(height: 32),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: ac.power ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !ac.power,
              child: Column(
                children: [
                  ModeButton(
                    mode: ac.mode,
                    accent: accent,
                    onTap: () => showModeSheet(
                      context,
                      modes: p.modes,
                      current: ac.mode,
                      accent: accent,
                      onSelected: ctrl.setMode,
                    ),
                  ),
                  if (p.windSteps.isNotEmpty) ...[
                    // Numbered speeds (1..5) + Auto, like the official app.
                    const SizedBox(height: 14),
                    PillSelector<int>(
                      options: [
                        if (p.windStrengths.contains('AUTO'))
                          const PillOption(0, 'Auto'),
                        for (final s in p.windSteps) PillOption(s, '$s'),
                      ],
                      selected: ac.fanSelection,
                      accent: accent,
                      onSelected: (v) =>
                          v == 0 ? ctrl.setWind('AUTO') : ctrl.setWindStep(v),
                    ),
                  ] else if (p.windStrengths.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    PillSelector<String>(
                      options: [
                        for (final w in p.windStrengths)
                          PillOption(w, _HomeScreenState._windLabels[w] ?? w),
                      ],
                      selected: ac.windStrength,
                      accent: accent,
                      onSelected: ctrl.setWind,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (p.canSwing) ...[
                        ToggleTile(
                          icon: Icons.swap_vert_rounded,
                          label: 'Swing',
                          active: ac.swing ?? false,
                          accent: accent,
                          onTap: ctrl.toggleSwing,
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (p.canDisplayLight) ...[
                        ToggleTile(
                          icon: Icons.light_mode_outlined,
                          label: 'Display',
                          active: ac.displayLight ?? false,
                          accent: accent,
                          onTap: ctrl.toggleDisplayLight,
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (p.canSleepTimer)
                        ToggleTile(
                          icon: Icons.bedtime_outlined,
                          label: 'Timer',
                          active: ac.sleepTimerSet,
                          accent: accent,
                          onTap: () => showSleepTimerSheet(
                            context,
                            active: ac.sleepTimerSet,
                            accent: accent,
                            onSet: ctrl.setSleepTimer,
                            onCancel: ctrl.cancelSleepTimer,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      if (wide) {
        return Row(
          children: [
            Expanded(child: Center(child: dial)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(child: controls),
              ),
            ),
          ],
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(children: [dial, const SizedBox(height: 12), controls]),
      );
    });
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: onSurface.withValues(alpha: 0.07),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: onSurface.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
                onPressed: onRetry, child: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }
}
