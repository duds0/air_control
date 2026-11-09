import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/models.dart';
import '../data/thinq_repository.dart';
import '../widget/ac_widget_service.dart';
import 'providers.dart';
import 'temp_step.dart';

export 'temp_step.dart';

/// One-shot message for the UI (identity matters, so each is shown once).
class Notice {
  Notice(this.text);
  final String text;
}

class AcViewState {
  const AcViewState({
    this.device,
    this.profile = AcProfile.fallback,
    this.ac,
    this.loading = true,
    this.offline = false,
    this.fatal,
    this.notice,
  });

  final ThinqDevice? device;
  final AcProfile profile;
  final AcState? ac;
  final bool loading;
  final bool offline;
  final String? fatal; // blocking error (e.g. no air conditioner found)
  final Notice? notice;

  AcViewState copyWith({
    ThinqDevice? device,
    AcProfile? profile,
    AcState? ac,
    bool? loading,
    bool? offline,
    String? fatal,
    Notice? notice,
  }) =>
      AcViewState(
        device: device ?? this.device,
        profile: profile ?? this.profile,
        ac: ac ?? this.ac,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        fatal: fatal,
        notice: notice,
      );
}

class AcController extends Notifier<AcViewState> {
  static const _pollEvery = Duration(seconds: 8);
  static const _settle = Duration(milliseconds: 1500);
  static const _tempDebounce = Duration(milliseconds: 600);

  Timer? _poll;
  Timer? _debounce;
  int _busy = 0;
  bool _paused = false;
  bool _disposed = false;

  ThinqRepository? get _repo => ref.read(repositoryProvider);

  @override
  AcViewState build() {
    ref.watch(repositoryProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _poll?.cancel();
      _debounce?.cancel();
    });
    Future.microtask(_init);
    return const AcViewState();
  }

  void _set(AcViewState s) {
    if (!_disposed) state = s;
  }

  Future<void> _init() async {
    final repo = _repo;
    if (repo == null || _disposed) return;
    try {
      final devices = await repo.devices();
      final ac = devices.where((d) => d.isAirConditioner).firstOrNull;
      if (ac == null) {
        _set(const AcViewState(
          loading: false,
          fatal: 'Nenhum ar-condicionado encontrado nesta conta.',
        ));
        return;
      }
      final results = await Future.wait([repo.profile(ac.id), repo.state(ac.id)]);
      _set(AcViewState(
        device: ac,
        profile: results[0] as AcProfile,
        ac: results[1] as AcState,
        loading: false,
      ));
      _syncWidget();
      _poll?.cancel();
      _poll = Timer.periodic(_pollEvery, (_) => refresh());
    } on ThinqException catch (e) {
      _handleError(e, blocking: true);
    }
  }

  void _handleError(ThinqException e, {bool blocking = false}) {
    if (e.unauthorized) {
      ref.read(credentialsProvider.notifier).signOut();
      return;
    }
    if (blocking) {
      _set(AcViewState(loading: false, fatal: e.message));
    } else {
      _set(state.copyWith(offline: true, loading: false));
    }
  }

  /// Polls the device state unless the user is mid-interaction.
  Future<void> refresh({bool force = false}) async {
    final repo = _repo;
    final id = state.device?.id;
    if (repo == null || id == null || _disposed) return;
    if (!force && (_paused || _busy > 0 || (_debounce?.isActive ?? false))) {
      return;
    }
    try {
      final ac = await repo.state(id);
      if (_busy > 0 || (_debounce?.isActive ?? false)) return; // stale
      _set(state.copyWith(ac: ac, offline: false, loading: false));
      _syncWidget();
    } on ThinqException catch (e) {
      _handleError(e);
    }
  }

  /// Keeps the home-screen widget in step with what the app just read.
  void _syncWidget() {
    final d = state.device;
    final ac = state.ac;
    if (d == null || ac == null) return;
    AcWidgetService.publish(device: d, profile: state.profile, ac: ac);
  }

  void pause() => _paused = true;

  void resume() {
    _paused = false;
    if (state.device == null && state.fatal != null) {
      _init();
    } else {
      refresh(force: true);
    }
  }

  Future<void> retry() async {
    _set(state.copyWith(loading: true, offline: false));
    if (state.device == null) {
      await _init();
    } else {
      await refresh(force: true);
    }
  }

  // ---- commands -----------------------------------------------------------

  void togglePower() {
    final ac = state.ac;
    if (ac == null) return;
    _command(ThinqRepository.power(!ac.power), (s) => s.copyWith(power: !s.power));
  }

  void setMode(String mode) => _command(
      ThinqRepository.mode(mode), (s) => s.copyWith(mode: mode));

  void setTargetTemp(double t) {
    final p = state.profile;
    final v = t.clamp(p.minTemp, p.maxTemp).toDouble();
    _command(
      ThinqRepository.targetTemp(v),
      (s) => s.copyWith(targetTemp: v),
      debounce: _tempDebounce,
    );
  }

  /// Moves the target to the next multiple of the chosen step.
  void nudgeTemp(int direction) {
    final ac = state.ac;
    if (ac == null) return;
    // Computed from own state: reading effectiveTempStepProvider here would
    // be circular (it depends on this controller).
    final p = state.profile;
    final step = resolveTempStep(p.tempStep, ref.read(tempStepProvider));
    setTargetTemp(steppedTemp(ac.targetTemp, step, direction,
        min: p.minTemp, max: p.maxTemp));
  }

  /// "Auto" (and legacy LOW/MID/HIGH on models without numbered speeds).
  void setWind(String w) => _command(
        ThinqRepository.wind(w),
        (s) => s.copyWith(windStrength: w, clearWindStep: w == 'AUTO'),
      );

  void setWindStep(int step) => _command(
        ThinqRepository.windStep(step),
        (s) => s.copyWith(windStep: step),
      );

  void toggleSwing() {
    final on = !(state.ac?.swing ?? false);
    _command(ThinqRepository.swing(on), (s) => s.copyWith(swing: on));
  }

  void toggleDisplayLight() {
    final on = !(state.ac?.displayLight ?? true);
    _command(ThinqRepository.displayLight(on),
        (s) => s.copyWith(displayLight: on));
  }

  /// "Turn off in" timer. The unit accepts 30 min and whole hours (1–12 h);
  /// it silently IGNORES a new value while one is active, so an active timer
  /// is cancelled first (verified on a real unit).
  void setSleepTimer(Duration d) => _commandAll(
        [
          if (state.ac?.sleepTimerSet ?? false)
            ThinqRepository.cancelSleepTimer(),
          ThinqRepository.sleepTimer(d.inHours, d.inMinutes % 60),
        ],
        (s) => s.copyWith(sleepFor: d),
      );

  void cancelSleepTimer() => _command(
        ThinqRepository.cancelSleepTimer(),
        (s) => s.copyWith(clearSleepFor: true),
      );

  /// "Turn on at" / "turn off at" a fixed time. Setting replaces an active
  /// timer directly (no cancel needed); cancelling needs UNSET.
  void setStartTimer(ClockTime t) => _command(
        ThinqRepository.startTimer(t.hour, t.minute),
        (s) => s.copyWith(startAt: t),
      );

  void cancelStartTimer() => _command(
        ThinqRepository.cancelStartTimer(),
        (s) => s.copyWith(clearStartAt: true),
      );

  void setStopTimer(ClockTime t) => _command(
        ThinqRepository.stopTimer(t.hour, t.minute),
        (s) => s.copyWith(stopAt: t),
      );

  void cancelStopTimer() => _command(
        ThinqRepository.cancelStopTimer(),
        (s) => s.copyWith(clearStopAt: true),
      );

  /// Applies [optimistic] immediately, then sends [body] (optionally
  /// debounced). The server state is re-read once the device has settled.
  void _command(
    Map<String, dynamic> body,
    AcState Function(AcState) optimistic, {
    Duration? debounce,
  }) =>
      _commandAll([body], optimistic, debounce: debounce);

  /// Like [_command] but sends several requests one after the other.
  void _commandAll(
    List<Map<String, dynamic>> bodies,
    AcState Function(AcState) optimistic, {
    Duration? debounce,
  }) {
    final ac = state.ac;
    if (ac == null) return;
    _set(state.copyWith(ac: optimistic(ac)));

    if (debounce != null) {
      _debounce?.cancel();
      _debounce = Timer(debounce, () => _send(bodies));
    } else {
      _send(bodies);
    }
  }

  Future<void> _send(List<Map<String, dynamic>> bodies) async {
    final repo = _repo;
    final id = state.device?.id;
    if (repo == null || id == null) return;
    _busy++;
    try {
      for (final body in bodies) {
        await repo.control(id, body);
      }
      await Future<void>.delayed(_settle);
    } on ThinqException catch (e) {
      if (e.unauthorized) {
        _handleError(e);
      } else {
        _set(state.copyWith(notice: Notice('Não foi possível enviar o comando.')));
      }
    } finally {
      _busy--;
    }
    await refresh();
  }
}

final acControllerProvider =
    NotifierProvider<AcController, AcViewState>(AcController.new);

final tempStepOptionsProvider = Provider<List<double>>((ref) {
  final step = ref.watch(acControllerProvider.select((s) => s.profile.tempStep));
  return tempStepOptions(step);
});

/// Increment used by the dial and the +/- buttons (UI side).
final effectiveTempStepProvider = Provider<double>((ref) {
  final step = ref.watch(acControllerProvider.select((s) => s.profile.tempStep));
  return resolveTempStep(step, ref.watch(tempStepProvider));
});
