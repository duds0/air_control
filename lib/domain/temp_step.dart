// Pure helpers for the temperature step, shared by the app and the home-screen
// widget (which runs in a background isolate without Riverpod/UI).

/// "25" for whole numbers, "24,5" otherwise (pt-BR decimal comma).
String formatTemp(double t) {
  final whole = t == t.roundToDouble();
  return whole ? t.toStringAsFixed(0) : t.toStringAsFixed(1).replaceAll('.', ',');
}

/// Selectable temperature increments: the device's own step, plus 1°.
List<double> tempStepOptions(double deviceStep) =>
    deviceStep < 1 ? [deviceStep, 1.0] : [deviceStep];

/// The increment in use: the user's choice if valid, else the device's step.
double resolveTempStep(double deviceStep, double? pref) {
  final options = tempStepOptions(deviceStep);
  return options.contains(pref) ? pref! : options.first;
}

/// Next multiple of [step] above (+1) or below (-1) [current], so switching
/// from 0.5° to 1° steps realigns 24.5 → 25 instead of 25.5. Clamped.
double steppedTemp(
  double current,
  double step,
  int direction, {
  required double min,
  required double max,
}) {
  final q = current / step;
  final n = direction > 0 ? (q + 1e-9).floor() + 1 : (q - 1e-9).ceil() - 1;
  return (n * step).clamp(min, max).toDouble();
}
