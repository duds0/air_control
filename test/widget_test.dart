import 'package:air_control/core/api_client.dart';
import 'package:air_control/core/secure_store.dart';
import 'package:air_control/data/models.dart';
import 'package:air_control/data/thinq_repository.dart';
import 'package:air_control/domain/ac_controller.dart';
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
