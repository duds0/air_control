import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/api_client.dart';
import '../core/errors.dart';
import '../core/secure_store.dart';
import '../data/models.dart';
import '../data/thinq_repository.dart';
import '../domain/fan_speed.dart';
import '../domain/temp_step.dart';

/// Android home-screen widget bridge.
///
/// The widget itself is native (res/layout/ac_widget.xml + AcWidgetProvider.kt):
/// it only draws what is stored under the keys below and, on tap, fires a
/// background callback ([widgetBackgroundCallback]) that talks to the LG API
/// using the same client as the app — the app never has to open.
class AcWidgetService {
  AcWidgetService._();

  static const _provider = 'br.com.hrzon.air_control.AcWidgetProvider';
  static const scheme = 'airwidget';

  /// Cached state older than this is re-read from the API before a toggle, so
  /// a stale cache can't make "Swing" flip the wrong way.
  static const _freshFor = Duration(seconds: 30);
  static const _settle = Duration(milliseconds: 1500);

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _modeLabels = {
    'COOL': 'Frio',
    'FAN': 'Ventilar',
    'AIR_DRY': 'Seco',
  };

  // ---- called by the app ----------------------------------------------------

  /// Registers the tap handler. Call once from main().
  static Future<void> init() async {
    if (!supported) return;
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    } catch (e) {
      debugPrint('Widget: falha ao registrar o callback: $e');
    }
  }

  /// Pushes the latest real state (from the app's polling) to the widget.
  static Future<void> publish({
    required ThinqDevice device,
    required AcProfile profile,
    required AcState ac,
    String? status,
  }) async {
    if (!supported) return;
    try {
      await _writeAll(
        _Ctx(device.id, device.alias, profile),
        ac,
        status: status,
      );
    } catch (e) {
      debugPrint('Widget: falha ao publicar: $e');
    }
  }

  /// Whether the launcher can add the widget straight from the app.
  static Future<bool> canPin() async {
    if (!supported) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the launcher to add the widget to the home screen (user confirms).
  static Future<void> requestPin() async {
    try {
      await HomeWidget.requestPinWidget(qualifiedAndroidName: _provider);
    } catch (e) {
      debugPrint('Widget: falha ao pedir para fixar: $e');
    }
  }

  /// Wipes the widget (sign-out): it goes back to "open the app".
  static Future<void> clear() async {
    if (!supported) return;
    try {
      await HomeWidget.saveWidgetData<bool>('w_has', false);
      await HomeWidget.saveWidgetData<String>('c_deviceId', '');
      await HomeWidget.saveWidgetData<String>('w_sig', '');
      await HomeWidget.saveWidgetData<String>(
          'w_status', 'Abra o app para conectar');
      await _refreshWidget();
    } catch (e) {
      debugPrint('Widget: falha ao limpar: $e');
    }
  }

  // ---- background taps ------------------------------------------------------

  static Future<void> _tail = Future.value();
  static Future<void>? _worker;
  static final Map<String, Map<String, dynamic>> _pending = {};

  /// Runs [f] after every previously queued call, so rapid taps read and write
  /// the cached state one at a time.
  static Future<T> _serial<T>(Future<T> Function() f) {
    final r = _tail.then((_) => f());
    _tail = r.then((_) {}, onError: (_) {});
    return r;
  }

  static Future<void> handle(Uri? uri) async {
    if (uri == null || uri.scheme != scheme) return;
    final store = SecureStore();
    final creds = await store.load();
    if (creds == null) {
      await HomeWidget.saveWidgetData<bool>('w_has', false);
      await HomeWidget.saveWidgetData<String>('w_sig', '');
      await HomeWidget.saveWidgetData<String>(
          'w_status', 'Abra o app para conectar');
      await _refreshWidget();
      return;
    }
    final repo = ThinqRepository(ThinqApiClient(creds));

    // Phase 1 (serialized): read cache, apply the tap optimistically, queue
    // the command. The widget updates immediately.
    var queued = false;
    final _Ctx ctx;
    try {
      ctx = await _serial(() async {
        final c = await _loadCtx(repo);
        var ac = await _loadState(repo, c, force: uri.host == 'refresh');
        final change = await _plan(uri, c, ac, store);
        if (change == null) {
          await _writeAll(c, ac, status: _statusFor(ac));
          return c;
        }
        ac = change.next;
        _expected = ac;
        _pending[change.key] = change.body; // queue first: blocks stale read-backs
        // No transient "sending…" text: the tap's own change is the feedback,
        // and the final confirmation then equals what is already on screen,
        // so it triggers no redraw at all.
        await _writeAll(c, ac, status: _statusFor(ac));
        queued = true;
        return c;
      });
    } on ThinqException catch (e) {
      await _showError(e);
      return;
    }

    // Phase 2: one worker drains the queue (latest value per property wins),
    // waits for the unit to settle, then publishes the real state.
    if (queued) {
      _ensureWorker(repo, ctx);
    } else if (uri.host == 'refresh' && _worker == null) {
      _worker = _refreshOnly(repo, ctx).whenComplete(() => _worker = null);
    }
    await _worker;
  }

  /// Starts the single sender if none is running. When it finishes it checks
  /// once more for taps that arrived at the last moment, so none is dropped.
  static void _ensureWorker(ThinqRepository repo, _Ctx ctx) {
    if (_worker != null) return;
    _worker = _drain(repo, ctx).whenComplete(() {
      _worker = null;
      if (_pending.isNotEmpty) _ensureWorker(repo, ctx);
    });
  }

  static Future<void> _refreshOnly(ThinqRepository repo, _Ctx ctx) async {
    try {
      final fresh = await repo.state(ctx.id);
      await _writeAll(ctx, fresh, status: _statusFor(fresh));
    } on ThinqException catch (e) {
      await _showError(e);
    }
  }

  /// What the widget currently shows after the latest tap (optimistic).
  static AcState? _expected;

  /// Sends queued commands (latest per property), waits for the unit to
  /// settle, and only then publishes the real state. While anything newer is
  /// queued, a read-back is never published: it would overwrite what the user
  /// just tapped with an older value (the "flicker").
  static Future<void> _drain(ThinqRepository repo, _Ctx ctx) async {
    try {
      final sent = <String>{};
      while (true) {
        while (_pending.isNotEmpty) {
          final batch = Map.of(_pending);
          _pending.clear();
          for (final e in batch.entries) {
            await repo.control(ctx.id, e.value);
            sent.add(e.key);
          }
        }
        await Future<void>.delayed(_settle);
        if (_pending.isNotEmpty) continue;

        // The LG cloud can lag: re-read a few times while it still reports
        // the old value, instead of flashing the old value on screen.
        AcState fresh = await repo.state(ctx.id);
        for (var i = 0; i < 3 && _pending.isEmpty; i++) {
          if (_matches(fresh, _expected, sent)) break;
          await Future<void>.delayed(_settle);
          if (_pending.isNotEmpty) break;
          fresh = await repo.state(ctx.id);
        }
        if (_pending.isNotEmpty) continue;

        await _writeAll(ctx, fresh, status: _statusFor(fresh));
        if (_pending.isNotEmpty) continue; // tapped while we were writing
        _expected = null;
        return;
      }
    } on ThinqException catch (e) {
      _pending.clear();
      await _showError(e);
      // Show the real state again so the widget doesn't keep a wrong guess.
      try {
        final fresh = await repo.state(ctx.id);
        await _writeAll(ctx, fresh, status: 'Falha ao enviar');
      } on ThinqException {
        // Keep the error message above.
      }
    }
  }

  /// Whether the unit already reports what we sent for each touched property.
  static bool _matches(AcState fresh, AcState? want, Set<String> keys) {
    if (want == null) return true;
    for (final k in keys) {
      final ok = switch (k) {
        'power' => fresh.power == want.power,
        'temp' => fresh.targetTemp == want.targetTemp,
        'wind' => fresh.fanSelection == want.fanSelection,
        'swing' => (fresh.swing ?? false) == (want.swing ?? false),
        'display' => (fresh.displayLight ?? true) == (want.displayLight ?? true),
        _ => true,
      };
      if (!ok) return false;
    }
    return true;
  }

  static Future<void> _showError(ThinqException e) async {
    await HomeWidget.saveWidgetData<String>(
      'w_status',
      e.unauthorized ? 'Token inválido' : 'Sem conexão com a LG',
    );
    // Not through _writeAll, so invalidate its signature: the next real state
    // must redraw even if it equals the one before the error.
    await HomeWidget.saveWidgetData<String>('w_sig', '');
    await _refreshWidget();
  }

  /// Translates a tap into (new optimistic state, command). Null = ignore.
  static Future<_Change?> _plan(
    Uri uri,
    _Ctx ctx,
    AcState ac,
    SecureStore store,
  ) async {
    final p = ctx.profile;
    switch (uri.host) {
      case 'power':
        final on = !ac.power;
        return _Change('power', ThinqRepository.power(on), ac.copyWith(power: on));
      case 'temp':
        if (!ac.power || ac.mode != 'COOL') return null;
        final d = int.tryParse(uri.queryParameters['d'] ?? '') ?? 0;
        if (d == 0) return null;
        final step = resolveTempStep(p.tempStep, await store.loadTempStep());
        final v = steppedTemp(ac.targetTemp, step, d, min: p.minTemp, max: p.maxTemp);
        return _Change('temp', ThinqRepository.targetTemp(v), ac.copyWith(targetTemp: v));
      case 'wind':
        if (!ac.power) return null;
        // "d=±1": the - / + stepper over Auto, 1..5 (Auto is the first value).
        final d = int.tryParse(uri.queryParameters['d'] ?? '');
        if (d == null) return null;
        final next = nextFanSpeed(
          current: ac.fanSelection,
          steps: p.windSteps,
          hasAuto: p.windStrengths.contains('AUTO'),
          direction: d,
        );
        if (next == null) return null;
        if (next == 0) {
          return _Change(
            'wind',
            ThinqRepository.wind('AUTO'),
            ac.copyWith(windStrength: 'AUTO', clearWindStep: true),
          );
        }
        return _Change('wind', ThinqRepository.windStep(next), ac.copyWith(windStep: next));
      case 'swing':
        if (!ac.power || !p.canSwing) return null;
        final on = !(ac.swing ?? false);
        return _Change('swing', ThinqRepository.swing(on), ac.copyWith(swing: on));
      case 'display':
        if (!ac.power || !p.canDisplayLight) return null;
        final on = !(ac.displayLight ?? true);
        return _Change(
            'display', ThinqRepository.displayLight(on), ac.copyWith(displayLight: on));
    }
    return null;
  }

  // ---- cache (what the widget also reads) ----------------------------------

  static Future<_Ctx> _loadCtx(ThinqRepository repo) async {
    final id = await HomeWidget.getWidgetData<String>('c_deviceId');
    if (id != null && id.isNotEmpty) {
      double d(String? s, double fb) => double.tryParse(s ?? '') ?? fb;
      final winds = (await HomeWidget.getWidgetData<String>('c_winds') ?? '')
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      return _Ctx(
        id,
        await HomeWidget.getWidgetData<String>('c_alias') ?? 'Ar-condicionado',
        AcProfile(
          modes: const ['COOL', 'FAN', 'AIR_DRY'],
          windStrengths: const ['AUTO'],
          windSteps: winds,
          minTemp: d(await HomeWidget.getWidgetData<String>('c_min'), 16),
          maxTemp: d(await HomeWidget.getWidgetData<String>('c_max'), 30),
          tempStep: d(await HomeWidget.getWidgetData<String>('c_step'), 0.5),
          canSwing: await HomeWidget.getWidgetData<bool>('c_canSwing') ?? false,
          canDisplayLight:
              await HomeWidget.getWidgetData<bool>('c_canDisplay') ?? false,
          canSleepTimer: false,
        ),
      );
    }
    // Never opened the app since installing: discover the unit ourselves.
    final device =
        (await repo.devices()).firstWhere((x) => x.isAirConditioner);
    return _Ctx(device.id, device.alias, await repo.profile(device.id));
  }

  static Future<AcState> _loadState(
    ThinqRepository repo,
    _Ctx ctx, {
    bool force = false,
  }) async {
    if (!force) {
      final at = int.tryParse(await HomeWidget.getWidgetData<String>('c_at') ?? '');
      final target =
          double.tryParse(await HomeWidget.getWidgetData<String>('s_target') ?? '');
      final fresh = at != null &&
          DateTime.now().millisecondsSinceEpoch - at < _freshFor.inMilliseconds;
      if (fresh && target != null) {
        final wind = int.tryParse(await HomeWidget.getWidgetData<String>('s_wind') ?? '');
        return AcState(
          power: await HomeWidget.getWidgetData<bool>('s_power') ?? false,
          mode: await HomeWidget.getWidgetData<String>('s_mode') ?? 'COOL',
          currentTemp:
              double.tryParse(await HomeWidget.getWidgetData<String>('s_current') ?? ''),
          targetTemp: target,
          windStrength: wind == 0 ? 'AUTO' : AcState.strengthForStep(wind ?? 1),
          windStep: (wind == null || wind == 0) ? null : wind,
          swing: await HomeWidget.getWidgetData<bool>('s_swing'),
          displayLight: await HomeWidget.getWidgetData<bool>('s_display'),
        );
      }
    }
    return repo.state(ctx.id);
  }

  static String _statusFor(AcState ac) {
    if (ac.hasError) return 'Aparelho reportou erro';
    if (!ac.power) return 'Desligado';
    final mode = _modeLabels[ac.mode] ?? ac.mode;
    final room = ac.currentTemp == null
        ? ''
        : ' · Ambiente ${formatTemp(ac.currentTemp!)}°';
    return '$mode$room';
  }

  /// Stores cache + display values, then asks the launcher to redraw.
  static Future<void> _writeAll(_Ctx ctx, AcState ac, {String? status}) async {
    final p = ctx.profile;
    final tempOk = ac.power && ac.mode == 'COOL';
    final big = !ac.power
        ? 'Off'
        : tempOk
            ? '${formatTemp(ac.targetTemp)}°'
            : (ac.currentTemp != null ? '${formatTemp(ac.currentTemp!)}°' : '—');
    final wind = ac.windStrength == 'AUTO' ? 0 : ac.windStep;

    final strings = <String, String>{
      'c_deviceId': ctx.id,
      'c_alias': ctx.alias,
      'c_min': '${p.minTemp}',
      'c_max': '${p.maxTemp}',
      'c_step': '${p.tempStep}',
      'c_winds': p.windSteps.join(','),
      'c_at': '${DateTime.now().millisecondsSinceEpoch}',
      's_mode': ac.mode,
      's_target': '${ac.targetTemp}',
      's_current': ac.currentTemp == null ? '' : '${ac.currentTemp}',
      's_wind': wind == null ? '' : '$wind',
      'w_title': ctx.alias,
      'w_status': status ?? _statusFor(ac),
      'w_big': big,
      'w_wind': wind == null ? '' : '$wind',
    };
    final bools = <String, bool>{
      'c_canSwing': p.canSwing,
      'c_canDisplay': p.canDisplayLight,
      's_power': ac.power,
      's_swing': ac.swing ?? false,
      's_display': ac.displayLight ?? true,
      'w_has': true,
      'w_power': ac.power,
      'w_tempOk': tempOk,
      'w_swing': ac.swing ?? false,
      'w_display': ac.displayLight ?? true,
      'w_canSwing': p.canSwing,
      'w_canDisplay': p.canDisplayLight,
    };
    // Signature of what is actually drawn (the w_* keys). Redrawing the widget
    // re-inflates it and can flash, so skip it when nothing visible changed
    // (e.g. the app's 8 s polling re-publishing the same state). Stored with
    // the data so the app and the background isolate share it.
    final sig = [
      for (final e in strings.entries)
        if (e.key.startsWith('w_')) '${e.key}=${e.value}',
      for (final e in bools.entries)
        if (e.key.startsWith('w_')) '${e.key}=${e.value}',
    ].join('|');
    final lastSig = await HomeWidget.getWidgetData<String>('w_sig');

    await Future.wait([
      for (final e in strings.entries)
        HomeWidget.saveWidgetData<String>(e.key, e.value),
      for (final e in bools.entries) HomeWidget.saveWidgetData<bool>(e.key, e.value),
    ]);
    if (sig == lastSig) return;
    await HomeWidget.saveWidgetData<String>('w_sig', sig);
    await _refreshWidget();
  }

  static Future<void> _refreshWidget() =>
      HomeWidget.updateWidget(qualifiedAndroidName: _provider);
}

class _Ctx {
  _Ctx(this.id, this.alias, this.profile);
  final String id;
  final String alias;
  final AcProfile profile;
}

class _Change {
  _Change(this.key, this.body, this.next);
  final String key; // one pending command per property: latest tap wins
  final Map<String, dynamic> body;
  final AcState next;
}

/// Entry point for taps on the home-screen widget; runs in a background
/// isolate started by the home_widget plugin (the app is not opened).
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) => AcWidgetService.handle(uri);
