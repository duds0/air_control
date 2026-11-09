import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/energy.dart';
import 'ac_controller.dart';
import 'providers.dart';

class EnergyViewState {
  const EnergyViewState({this.supported, this.days = const []});

  /// null = not known yet; false = this unit has no energy data (hide it).
  final bool? supported;

  /// Last 31 days, oldest first; the last entry is today (so far).
  final List<EnergyDay> days;

  EnergyDay? get today {
    if (days.isEmpty) return null;
    return days.last.isSameDay(DateTime.now()) ? days.last : null;
  }
}

/// Loads energy usage and keeps "today" fresh. The API reports a running
/// total for the day (no instantaneous watts), which grows as the unit runs.
class EnergyController extends Notifier<EnergyViewState> {
  static const _every = Duration(seconds: 60);

  Timer? _timer;
  bool _paused = false;
  bool _disposed = false;

  @override
  EnergyViewState build() {
    _disposed = false;
    final repo = ref.watch(repositoryProvider);
    final id = ref.watch(acControllerProvider.select((s) => s.device?.id));
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    if (repo != null && id != null) Future.microtask(_start);
    return const EnergyViewState();
  }

  Future<void> _start() async {
    final repo = ref.read(repositoryProvider);
    final id = ref.read(acControllerProvider).device?.id;
    if (repo == null || id == null || _disposed) return;
    try {
      final ok = await repo.energySupported(id);
      if (_disposed) return;
      if (!ok) {
        state = const EnergyViewState(supported: false);
        return;
      }
      state = EnergyViewState(supported: true, days: state.days);
      await refresh();
      _timer?.cancel();
      _timer = Timer.periodic(_every, (_) => refresh());
    } on ThinqException {
      // Energy is a nice-to-have: stay quiet and try again on resume.
    }
  }

  Future<void> refresh() async {
    final repo = ref.read(repositoryProvider);
    final id = ref.read(acControllerProvider).device?.id;
    if (repo == null || id == null || _disposed || _paused) return;
    if (state.supported != true) return;
    try {
      final days = await repo.energyDaily(id);
      if (_disposed) return;
      state = EnergyViewState(supported: true, days: days);
    } on ThinqException {
      // Keep showing the last values.
    }
  }

  void pause() => _paused = true;

  void resume() {
    _paused = false;
    if (state.supported == null) {
      _start();
    } else {
      refresh();
    }
  }
}

final energyControllerProvider =
    NotifierProvider<EnergyController, EnergyViewState>(EnergyController.new);
