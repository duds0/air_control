/// A ThinQ device from `GET /devices`.
class ThinqDevice {
  const ThinqDevice({
    required this.id,
    required this.type,
    required this.alias,
    required this.model,
  });

  final String id;
  final String type;
  final String alias;
  final String model;

  bool get isAirConditioner => type == 'DEVICE_AIR_CONDITIONER';

  factory ThinqDevice.fromJson(Map<String, dynamic> j) {
    final info = (j['deviceInfo'] as Map?)?.cast<String, dynamic>() ?? {};
    return ThinqDevice(
      id: j['deviceId'] as String,
      type: info['deviceType'] as String? ?? '',
      alias: info['alias'] as String? ?? 'Ar-condicionado',
      model: info['modelName'] as String? ?? '',
    );
  }
}

/// Current AC state, mirroring `GET /devices/{id}/state`.
class AcState {
  const AcState({
    required this.power,
    required this.mode,
    required this.currentTemp,
    required this.targetTemp,
    this.windStrength,
    this.windStep,
    this.swing,
    this.displayLight,
    this.sleepTimerSet = false,
    this.hasError = false,
  });

  final bool power;
  final String mode; // COOL | FAN | AIR_DRY ...
  final double? currentTemp;
  final double targetTemp;
  final String? windStrength; // LOW | MID | HIGH | AUTO
  final int? windStep; // 1..5, absent while AUTO
  final bool? swing;
  final bool? displayLight;
  final bool sleepTimerSet;
  final bool hasError;

  factory AcState.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(String k) =>
        (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final temp = m('temperature');
    final light = m('display')['light'];
    return AcState(
      power: m('operation')['airConOperationMode'] == 'POWER_ON',
      mode: m('airConJobMode')['currentJobMode'] as String? ?? 'COOL',
      currentTemp: (temp['currentTemperature'] as num?)?.toDouble(),
      targetTemp: (temp['targetTemperature'] as num?)?.toDouble() ?? 24,
      windStrength: m('airFlow')['windStrength'] as String?,
      windStep: (m('airFlow')['windStep'] as num?)?.toInt(),
      swing: m('windDirection')['rotateUpDown'] as bool?,
      displayLight: light == null ? null : light == 'ON',
      sleepTimerSet: m('sleepTimer')['relativeStopTimer'] == 'SET',
      hasError: m('runState')['currentState'] == 'ERROR',
    );
  }

  /// Best-effort LOW/MID/HIGH for a numbered speed, used only until the next
  /// poll replaces it with the device's real value.
  static String strengthForStep(int step) =>
      step <= 2 ? 'LOW' : (step == 3 ? 'MID' : 'HIGH');

  /// What the fan selector shows: 0 = Auto, otherwise the numbered speed.
  int? get fanSelection => windStrength == 'AUTO' ? 0 : windStep;

  AcState copyWith({
    bool? power,
    String? mode,
    double? targetTemp,
    String? windStrength,
    int? windStep,
    bool clearWindStep = false,
    bool? swing,
    bool? displayLight,
    bool? sleepTimerSet,
  }) =>
      AcState(
        power: power ?? this.power,
        mode: mode ?? this.mode,
        currentTemp: currentTemp,
        targetTemp: targetTemp ?? this.targetTemp,
        // Picking a numbered speed leaves AUTO immediately (optimistic): the
        // two fields describe one thing, so they must change together.
        windStrength: windStrength ??
            (windStep != null ? strengthForStep(windStep) : this.windStrength),
        windStep: clearWindStep ? null : (windStep ?? this.windStep),
        swing: swing ?? this.swing,
        displayLight: displayLight ?? this.displayLight,
        sleepTimerSet: sleepTimerSet ?? this.sleepTimerSet,
        hasError: hasError,
      );
}

/// Writable capabilities parsed from `GET /devices/{id}/profile`.
/// The UI only shows controls the device actually supports.
class AcProfile {
  const AcProfile({
    required this.modes,
    required this.windStrengths,
    this.windSteps = const [],
    required this.minTemp,
    required this.maxTemp,
    required this.tempStep,
    required this.canSwing,
    required this.canDisplayLight,
    required this.canSleepTimer,
  });

  final List<String> modes;
  final List<String> windStrengths;

  /// Numbered fan speeds (e.g. 1..5) from `airFlow.windStep`; empty if the
  /// model has none. Speed "auto" is `windStrengths` containing 'AUTO'.
  final List<int> windSteps;
  final double minTemp;
  final double maxTemp;
  final double tempStep;
  final bool canSwing;
  final bool canDisplayLight;
  final bool canSleepTimer;

  static const fallback = AcProfile(
    modes: ['COOL', 'FAN', 'AIR_DRY'],
    windStrengths: ['AUTO', 'LOW', 'MID', 'HIGH'],
    minTemp: 18,
    maxTemp: 30,
    tempStep: 1,
    canSwing: false,
    canDisplayLight: false,
    canSleepTimer: false,
  );

  factory AcProfile.fromJson(Map<String, dynamic> j) {
    final prop = (j['property'] as Map?)?.cast<String, dynamic>() ?? {};

    Map<String, dynamic>? node(String group, String key) {
      final g = prop[group];
      if (g is! Map) return null;
      final n = g[key];
      return n is Map ? n.cast<String, dynamic>() : null;
    }

    bool writable(Map<String, dynamic>? n) =>
        n != null && (n['mode'] as List?)?.contains('w') == true;

    List<String> enumW(Map<String, dynamic>? n) {
      if (!writable(n)) return const [];
      final w = (n!['value'] as Map?)?['w'];
      return w is List ? w.cast<String>() : const [];
    }

    final target = node('temperature', 'targetTemperature');
    final range = writable(target)
        ? ((target!['value'] as Map?)?['w'] as Map?)?.cast<String, dynamic>()
        : null;

    final modes = enumW(node('airConJobMode', 'currentJobMode'));
    final winds = enumW(node('airFlow', 'windStrength'));

    final stepNode = node('airFlow', 'windStep');
    final stepRange = writable(stepNode)
        ? ((stepNode!['value'] as Map?)?['w'] as Map?)?.cast<String, dynamic>()
        : null;
    final steps = <int>[];
    if (stepRange != null) {
      final lo = (stepRange['min'] as num?)?.toInt() ?? 1;
      final hi = (stepRange['max'] as num?)?.toInt() ?? lo;
      final inc = (stepRange['step'] as num?)?.toInt() ?? 1;
      for (var v = lo; v <= hi; v += inc < 1 ? 1 : inc) {
        steps.add(v);
      }
    }

    return AcProfile(
      modes: modes.isEmpty ? fallback.modes : modes,
      windStrengths: winds,
      windSteps: steps,
      minTemp: (range?['min'] as num?)?.toDouble() ?? fallback.minTemp,
      maxTemp: (range?['max'] as num?)?.toDouble() ?? fallback.maxTemp,
      tempStep: (range?['step'] as num?)?.toDouble() ?? fallback.tempStep,
      canSwing: writable(node('windDirection', 'rotateUpDown')),
      canDisplayLight: writable(node('display', 'light')),
      canSleepTimer: writable(node('sleepTimer', 'relativeHourToStop')),
    );
  }
}
