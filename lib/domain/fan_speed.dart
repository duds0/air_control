/// Fan speeds as ONE ordered sequence: Auto, 1, 2, ... N (Auto is "0").
///
/// [current] is 0 for Auto, a step number, or null if unknown (treated as the
/// first entry). [direction] is +1 / -1. Returns the speed to switch to, or
/// null when already at an end (no wrap-around) or there is nothing to step.
///
///   Auto +  -> 1      1 -  -> Auto      Auto -  -> (none)      N +  -> (none)
int? nextFanSpeed({
  required int? current,
  required List<int> steps,
  required bool hasAuto,
  required int direction,
}) {
  final seq = [if (hasAuto) 0, ...steps];
  if (seq.isEmpty || direction == 0) return null;
  final at = current == null ? 0 : seq.indexOf(current);
  final next = (at < 0 ? 0 : at) + direction.sign;
  if (next < 0 || next >= seq.length) return null;
  return seq[next];
}
