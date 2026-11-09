import 'package:air_control/core/api_client.dart';
import 'package:air_control/core/secure_store.dart';
import 'package:air_control/data/energy.dart';
import 'package:air_control/data/models.dart';
import 'package:air_control/data/thinq_repository.dart';
import 'package:air_control/domain/ac_controller.dart';
import 'package:air_control/domain/fan_speed.dart';
import 'package:air_control/domain/providers.dart';
import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Trimmed real responses from a RAC_0B0001_WW unit.
const _state = {
  'runState': {'currentState': 'NORMAL'},
  'airConJobMode': {'currentJobMode': 'COOL'},
  'temperature': {'currentTemperature': 26.5, 'targetTemperature': 25, 'unit': 'C'},
  'airFlow': {'windStrength': 'AUTO', 'windStrengthDetail': 'NATURE'},
  'windDirection': {'rotateUpDown': true},
  'operation': {'airConOperationMode': 'POWER_ON'},
  'sleepTimer': {'relativeStopTimer': 'UNSET'},
  'display': {'light': 'ON'},
};

const _profile = {
  'property': {
    'airConJobMode': {
      'currentJobMode': {
        'type': 'enum',
        'mode': ['r', 'w'],
        'value': {
          'w': ['FAN', 'COOL', 'AIR_DRY'],
        },
      },
    },
    'temperature': {
      'targetTemperature': {
        'type': 'range',
        'mode': ['r', 'w'],
        'value': {
          'w': {'max': 30, 'min': 16, 'step': 0.5},
        },
      },
    },
    'airFlow': {
      'windStrength': {
        'type': 'enum',
        'mode': ['r', 'w'],
        'value': {
          'w': ['LOW', 'MID', 'HIGH', 'AUTO'],
        },
      },
      'windStep': {
        'type': 'range',
        'mode': ['r', 'w'],
        'value': {
          'w': {'max': 5, 'min': 1, 'step': 1},
        },
      },
    },
    'windDirection': {
      'rotateUpDown': {'type': 'boolean', 'mode': ['r', 'w']},
    },
    'display': {
      'light': {'type': 'enum', 'mode': ['r', 'w']},
    },
    'sleepTimer': {
      'relativeHourToStop': {'type': 'number', 'mode': ['r', 'w']},
    },
  },
};

/// Controller seeded with a state, no network (repository is null).
class _SeededController extends AcController {
  @override
  AcViewState build() {
    super.build();
    return const AcViewState(
      loading: false,
      profile: AcProfile(
        modes: ['COOL'],
        windStrengths: [],
        minTemp: 16,
        maxTemp: 30,
        tempStep: 0.5,
        canSwing: false,
        canDisplayLight: false,
        canSleepTimer: false,
      ),
      ac: AcState(
        power: true,
        mode: 'COOL',
        currentTemp: 26,
        targetTemp: 24.5,
      ),
    );
  }
}

/// In-memory stand-in for the platform secure storage.
class _MemStore extends SecureStore {
  double? step;
  @override
  Future<double?> loadTempStep() async => step;
  @override
  Future<void> saveTempStep(double s) async => step = s;

  String? theme;
  @override
  Future<String?> loadThemeMode() async => theme;
  @override
  Future<void> saveThemeMode(String m) async => theme = m;
}

void main() {
  test('theme toggle flips what is on screen and survives a restart', () async {
    final disk = _MemStore();
    ProviderContainer boot() => ProviderContainer(overrides: [
          secureStoreProvider.overrideWithValue(disk),
          initialThemeModeProvider.overrideWithValue(
            ThemeModeNotifier.parse(disk.theme),
          ),
        ]);

    // First run: follows the system. System is light -> toggle goes dark.
    final s1 = boot();
    expect(s1.read(themeModeProvider), ThemeMode.system);
    await s1.read(themeModeProvider.notifier).toggle(Brightness.light);
    expect(s1.read(themeModeProvider), ThemeMode.dark);
    expect(disk.theme, 'dark');

    // Toggling while dark goes back to light.
    await s1.read(themeModeProvider.notifier).toggle(Brightness.dark);
    expect(s1.read(themeModeProvider), ThemeMode.light);
    await s1.read(themeModeProvider.notifier).toggle(Brightness.light);
    s1.dispose();

    // Restart: the saved choice is restored.
    final s2 = boot();
    addTearDown(s2.dispose);
    expect(s2.read(themeModeProvider), ThemeMode.dark);

    expect(ThemeModeNotifier.parse(null), ThemeMode.system);
    expect(ThemeModeNotifier.parse('garbage'), ThemeMode.system);
  });

  test('temperature step survives an app restart', () async {
    final disk = _MemStore();

    // Session 1: nothing saved yet; user picks 1°.
    final s1 = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(disk),
      initialTempStepProvider.overrideWithValue(await disk.loadTempStep()),
    ]);
    expect(s1.read(tempStepProvider), isNull);
    await s1.read(tempStepProvider.notifier).set(1.0);
    expect(s1.read(tempStepProvider), 1.0);
    s1.dispose();

    // Session 2 (restart): main() loads from storage and seeds the provider.
    final s2 = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(disk),
      initialTempStepProvider.overrideWithValue(await disk.loadTempStep()),
    ]);
    addTearDown(s2.dispose);
    expect(s2.read(tempStepProvider), 1.0);
    expect(resolveTempStep(0.5, s2.read(tempStepProvider)), 1.0);
  });

  test('x-message-id is 22 chars url-safe base64 without padding', () {
    for (var i = 0; i < 50; i++) {
      final id = newMessageId();
      expect(id.length, 22);
      expect(RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(id), isTrue);
    }
  });

  test('AcState parses real state', () {
    final s = AcState.fromJson(_state);
    expect(s.power, isTrue);
    expect(s.mode, 'COOL');
    expect(s.currentTemp, 26.5);
    expect(s.targetTemp, 25);
    expect(s.windStrength, 'AUTO');
    expect(s.swing, isTrue);
    expect(s.displayLight, isTrue);
    expect(s.sleepTimerSet, isFalse);
    expect(s.hasError, isFalse);
  });

  test('AcState reads numbered fan speed', () {
    final s = AcState.fromJson({
      ..._state,
      'airFlow': {'windStrength': 'MID', 'windStrengthDetail': 'MID', 'windStep': 3},
    });
    expect(s.windStep, 3);
    expect(AcState.fromJson(_state).windStep, isNull); // AUTO has no step
  });

  test('fan selection flips immediately between Auto and numbered speeds', () {
    final auto = AcState.fromJson(_state); // windStrength AUTO
    expect(auto.fanSelection, 0);

    final toThree = auto.copyWith(windStep: 3); // optimistic: AUTO -> 3
    expect(toThree.fanSelection, 3);

    final toFive = toThree.copyWith(windStep: 5);
    expect(toFive.fanSelection, 5);

    final back = toFive.copyWith(windStrength: 'AUTO', clearWindStep: true);
    expect(back.fanSelection, 0);
  });

  test('AcProfile exposes only writable capabilities', () {
    final p = AcProfile.fromJson(_profile);
    expect(p.modes, ['FAN', 'COOL', 'AIR_DRY']);
    expect(p.windStrengths, ['LOW', 'MID', 'HIGH', 'AUTO']);
    expect(p.windSteps, [1, 2, 3, 4, 5]);
    expect((p.minTemp, p.maxTemp, p.tempStep), (16.0, 30.0, 0.5));
    expect(p.canSwing && p.canDisplayLight && p.canSleepTimer, isTrue);

    final empty = AcProfile.fromJson({'property': {}});
    expect(empty.canSwing, isFalse);
    expect(empty.windStrengths, isEmpty);
  });

  test('temperature step resolution', () {
    expect(tempStepOptions(0.5), [0.5, 1.0]);
    expect(tempStepOptions(1), [1.0]);
    expect(resolveTempStep(0.5, null), 0.5);
    expect(resolveTempStep(0.5, 1.0), 1.0);
    expect(resolveTempStep(1, 0.5), 1.0); // invalid preference ignored
  });

  test('nudgeTemp works through the real provider graph (no cycle)', () async {
    final container = ProviderContainer(overrides: [
      acControllerProvider.overrideWith(_SeededController.new),
      secureStoreProvider.overrideWithValue(_MemStore()),
      initialTempStepProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);

    final ctrl = container.read(acControllerProvider.notifier);
    double target() => container.read(acControllerProvider).ac!.targetTemp;

    expect(target(), 24.5);
    ctrl.nudgeTemp(1); // device step 0.5
    expect(target(), 25.0);

    await container.read(tempStepProvider.notifier).set(1.0);
    ctrl.nudgeTemp(1);
    expect(target(), 26.0);
    ctrl.nudgeTemp(-1);
    expect(target(), 25.0);

    // 24.5 with 1° step realigns to a whole degree.
    ctrl.setTargetTemp(24.5);
    ctrl.nudgeTemp(1);
    expect(target(), 25.0);
    ctrl.setTargetTemp(24.5);
    ctrl.nudgeTemp(-1);
    expect(target(), 24.0);
  });

  test('steppedTemp (shared by app and home-screen widget)', () {
    double up(double c, double s) => steppedTemp(c, s, 1, min: 16, max: 30);
    double down(double c, double s) => steppedTemp(c, s, -1, min: 16, max: 30);

    expect(up(25, 0.5), 25.5);
    expect(down(25, 0.5), 24.5);
    expect(up(24.5, 1), 25); // realigns to a whole degree
    expect(down(24.5, 1), 24);
    expect(up(30, 1), 30); // clamped to the unit's range
    expect(down(16, 0.5), 16);
    expect(formatTemp(24.5), '24,5');
    expect(formatTemp(25), '25');
  });

  test('fan speed is one sequence: Auto, 1..5 (widget stepper)', () {
    const steps = [1, 2, 3, 4, 5];
    int? next(int? cur, int dir, {bool auto = true}) => nextFanSpeed(
        current: cur, steps: steps, hasAuto: auto, direction: dir);

    expect(next(0, 1), 1); // Auto +  -> 1
    expect(next(1, -1), 0); // 1 -   -> Auto
    expect(next(0, -1), isNull); // Auto -  -> nothing
    expect(next(5, 1), isNull); // 5 +    -> nothing (no wrap)
    expect(next(3, 1), 4);
    expect(next(3, -1), 2);
    expect(next(null, 1), 1); // unknown is treated as Auto

    // A unit without Auto: 1 is the first value and the floor.
    expect(next(1, -1, auto: false), isNull);
    expect(next(1, 1, auto: false), 2);
    expect(nextFanSpeed(current: 0, steps: const [], hasAuto: false, direction: 1),
        isNull);
  });

  test('energy: parses the real daily response (energyUsage, not useAmount)', () {
    // Trimmed from a real response of GET .../energy/{id}/usage?period=DAILY.
    final days = parseEnergyDays({
      'resultCode': '0000',
      'result': {
        'property': ['energyUsage'],
        'dataList': [
          {'energyUsage': 4893, 'usedDate': '20261108'},
          {'energyUsage': 3274, 'usedDate': '20261010'}, // out of order
          {'energyUsage': 2653, 'usedDate': '20261109'},
          {'usedDate': 'garbage', 'energyUsage': 1}, // ignored
          {'usedDate': '20261107', 'useAmount': 6723}, // spec's field name
        ],
      },
    });
    expect(days.map((d) => ymd(d.date)),
        ['20261010', '20261107', '20261108', '20261109']);
    expect(days.last.wh, 2653);
    expect(days.last.isSameDay(DateTime(2026, 11, 9, 17, 30)), isTrue);
    expect(parseEnergyDays({}), isEmpty);
  });

  test('energy: 31-day range matches what the LG API accepted', () {
    final r = energyRange(DateTime(2026, 11, 9, 14, 5));
    expect((r.start, r.end), ('20261010', '20261109'));
    // Crossing a month/year boundary.
    final y = energyRange(DateTime(2027, 1, 10), days: 31);
    expect((y.start, y.end), ('20261211', '20270110'));
    expect(energyRange(DateTime(2026, 11, 9), days: 1).start, '20261109');
  });

  test('energy: kWh formatting (Wh in, pt-BR out)', () {
    expect(formatKwh(2653), '2,65 kWh');
    expect(formatKwh(513), '0,51 kWh');
    expect(formatKwh(0), '0,00 kWh');
    expect(formatKwh(10250), '10,3 kWh'); // one decimal from 10 kWh up
    expect(formatDayMonth(DateTime(2026, 11, 9)), '09/11');
  });

  test('timers: parsed from the real state/profile of the unit', () {
    // Real responses (trimmed): armed timers carry their hour/minute.
    final armed = AcState.fromJson({
      ..._state,
      'timer': {
        'absoluteStartTimer': 'SET',
        'absoluteHourToStart': 6,
        'absoluteMinuteToStart': 30,
        'absoluteStopTimer': 'SET',
        'absoluteHourToStop': 23,
        'absoluteMinuteToStop': 5,
      },
      'sleepTimer': {
        'relativeStopTimer': 'SET',
        'relativeHourToStop': 2,
        'relativeMinuteToStop': 0,
      },
    });
    expect(armed.startAt, const ClockTime(6, 30));
    expect(armed.startAt!.label, '06:30');
    expect(armed.stopAt!.label, '23:05');
    expect(armed.sleepFor, const Duration(hours: 2));
    expect(armed.anyTimerSet, isTrue);

    // Real "nothing armed" state: no leftover hour/minute is read.
    final idle = AcState.fromJson({
      ..._state,
      'timer': {'absoluteStartTimer': 'UNSET', 'absoluteStopTimer': 'UNSET'},
    });
    expect(idle.startAt, isNull);
    expect(idle.stopAt, isNull);
    expect(idle.anyTimerSet, isFalse);

    // Optimistic edits and clears.
    final set = idle.copyWith(startAt: const ClockTime(7, 0));
    expect(set.startAt!.label, '07:00');
    expect(set.copyWith(clearStartAt: true).startAt, isNull);
    expect(set.copyWith(stopAt: const ClockTime(8, 0)).startAt!.label, '07:00');

    // Capabilities come from what the profile marks writable.
    final p = AcProfile.fromJson({
      'property': {
        'timer': {
          'absoluteHourToStart': {'type': 'number', 'mode': ['r', 'w']},
          'absoluteHourToStop': {'type': 'number', 'mode': ['r']},
        },
      },
    });
    expect(p.canStartTimer, isTrue);
    expect(p.canStopTimer, isFalse);
    expect(p.hasAnyTimer, isTrue);
    expect(AcProfile.fromJson({'property': {}}).hasAnyTimer, isFalse);
  });

  test('timers: payloads (start and stop are separate requests)', () {
    expect(ThinqRepository.startTimer(6, 30), {
      'timer': {'absoluteHourToStart': 6, 'absoluteMinuteToStart': 30},
    });
    expect(ThinqRepository.stopTimer(23, 5), {
      'timer': {'absoluteHourToStop': 23, 'absoluteMinuteToStop': 5},
    });
    expect(ThinqRepository.cancelStartTimer(), {
      'timer': {'absoluteStartTimer': 'UNSET'},
    });
    expect(ThinqRepository.cancelStopTimer(), {
      'timer': {'absoluteStopTimer': 'UNSET'},
    });
    // 30 min is hour 0 / minute 30 (accepted by the unit); whole hours use 0.
    expect(ThinqRepository.sleepTimer(0, 30), {
      'sleepTimer': {'relativeHourToStop': 0, 'relativeMinuteToStop': 30},
    });
  });

  test('command payloads', () {
    expect(ThinqRepository.power(true), {
      'operation': {'airConOperationMode': 'POWER_ON'},
    });
    expect(ThinqRepository.windStep(3), {
      'airFlow': {'windStep': 3},
    });
    expect(ThinqRepository.targetTemp(24.5), {
      'temperature': {'targetTemperature': 24.5, 'unit': 'C'},
    });
    expect(ThinqRepository.sleepTimer(1, 30), {
      'sleepTimer': {'relativeHourToStop': 1, 'relativeMinuteToStop': 30},
    });
  });
}
