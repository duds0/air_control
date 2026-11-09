import '../core/api_client.dart';
import 'energy.dart';
import 'models.dart';

class ThinqRepository {
  ThinqRepository(this._api);

  final ThinqApiClient _api;

  Future<List<ThinqDevice>> devices() async {
    final res = await _api.get('/devices');
    return (res as List)
        .map((e) => ThinqDevice.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<AcProfile> profile(String id) async {
    final res = await _api.get('/devices/$id/profile');
    return AcProfile.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<AcState> state(String id) async {
    final res = await _api.get('/devices/$id/state');
    return AcState.fromJson((res as Map).cast<String, dynamic>());
  }

  /// Whether this unit reports energy usage (resultCode 0000 + energyUsage).
  Future<bool> energySupported(String id) async {
    final res = await _api.get('/devices/energy/$id/profile');
    if (res is! Map) return false;
    final props = (res['result'] as Map?)?['property'];
    return res['resultCode'] == '0000' &&
        props is List &&
        props.contains('energyUsage');
  }

  /// Daily usage for the last [days] days (max 31), oldest first.
  Future<List<EnergyDay>> energyDaily(
    String id, {
    int days = 31,
    DateTime? now,
  }) async {
    final r = energyRange(now ?? DateTime.now(), days: days);
    final res = await _api.get(
      '/devices/energy/$id/usage?period=DAILY&startDate=${r.start}&endDate=${r.end}',
    );
    return res is Map ? parseEnergyDays(res.cast<String, dynamic>()) : const [];
  }

  Future<void> control(String id, Map<String, dynamic> body) =>
      _api.post('/devices/$id/control', body);

  // Command payloads (validated against a real RAC_0B0001_WW unit).
  static Map<String, dynamic> power(bool on) => {
        'operation': {'airConOperationMode': on ? 'POWER_ON' : 'POWER_OFF'},
      };
  static Map<String, dynamic> mode(String m) => {
        'airConJobMode': {'currentJobMode': m},
      };
  static Map<String, dynamic> targetTemp(double t) => {
        'temperature': {'targetTemperature': t, 'unit': 'C'},
      };
  static Map<String, dynamic> wind(String w) => {
        'airFlow': {'windStrength': w},
      };
  static Map<String, dynamic> windStep(int step) => {
        'airFlow': {'windStep': step},
      };
  static Map<String, dynamic> swing(bool on) => {
        'windDirection': {'rotateUpDown': on},
      };
  static Map<String, dynamic> displayLight(bool on) => {
        'display': {'light': on ? 'ON' : 'OFF'},
      };
  static Map<String, dynamic> sleepTimer(int hours, int minutes) => {
        'sleepTimer': {
          'relativeHourToStop': hours,
          'relativeMinuteToStop': minutes,
        },
      };
  static Map<String, dynamic> cancelSleepTimer() => {
        'sleepTimer': {'relativeStopTimer': 'UNSET'},
      };

  // "Turn on at" / "turn off at" (verified on a real unit): sending hour and
  // minute arms the timer (and replaces an active one); `...Timer: UNSET`
  // cancels it. Start and stop must be sent as separate requests: together
  // the LG API rejects them (2207).
  static Map<String, dynamic> startTimer(int hour, int minute) => {
        'timer': {'absoluteHourToStart': hour, 'absoluteMinuteToStart': minute},
      };
  static Map<String, dynamic> stopTimer(int hour, int minute) => {
        'timer': {'absoluteHourToStop': hour, 'absoluteMinuteToStop': minute},
      };
  static Map<String, dynamic> cancelStartTimer() => {
        'timer': {'absoluteStartTimer': 'UNSET'},
      };
  static Map<String, dynamic> cancelStopTimer() => {
        'timer': {'absoluteStopTimer': 'UNSET'},
      };
}
