// Energy usage from the ThinQ Energy API (GET /devices/energy/{id}/usage).
//
// Verified against a real RAC_0B0001_WW unit, which differs from openapi.json:
//  * the spec says only WashTower/WashCombo have energy data; the AC does;
//  * each entry is {"usedDate": "20261109", "energyUsage": 2653} (the spec
//    says `useAmount`; both are accepted here);
//  * DAILY accepts at most 31 days; MONTHLY was unreliable (returned 0 for a
//    month with consumption and rejected other ranges), so it is not used;
//  * the unit is not documented. Values are treated as Wh (a 31-day total of
//    ~107,000 = ~107 kWh is realistic for an air conditioner).
//
// There is no instantaneous power (watts): "today so far" is the closest.

class EnergyDay {
  const EnergyDay(this.date, this.wh);

  final DateTime date; // local calendar day, time 00:00
  final double wh;

  double get kwh => wh / 1000;

  bool isSameDay(DateTime other) =>
      date.year == other.year &&
      date.month == other.month &&
      date.day == other.day;
}

/// "20261109"
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? parseYmd(String s) {
  if (s.length != 8) return null;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// The last [days] days ending today, inclusive (the API allows at most 31).
({String start, String end}) energyRange(DateTime today, {int days = 31}) {
  final end = DateTime(today.year, today.month, today.day);
  final start = DateTime(end.year, end.month, end.day - (days - 1));
  return (start: ymd(start), end: ymd(end));
}

/// Parses the `response` of the usage endpoint into days, oldest first.
List<EnergyDay> parseEnergyDays(Map<String, dynamic> response) {
  final list = (response['result'] as Map?)?['dataList'];
  if (list is! List) return const [];
  final out = <EnergyDay>[];
  for (final e in list) {
    if (e is! Map) continue;
    final date = parseYmd((e['usedDate'] as String?) ?? '');
    final v = e['energyUsage'] ?? e['useAmount'];
    if (date == null || v is! num) continue;
    out.add(EnergyDay(date, v.toDouble()));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// "2,65 kWh" (two decimals below 10 kWh, one above), pt-BR decimal comma.
String formatKwh(double wh) {
  final k = wh / 1000;
  final s = k >= 10 ? k.toStringAsFixed(1) : k.toStringAsFixed(2);
  return '${s.replaceAll('.', ',')} kWh';
}

String formatDayMonth(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
