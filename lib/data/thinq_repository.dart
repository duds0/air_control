import '../core/api_client.dart';
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
}
