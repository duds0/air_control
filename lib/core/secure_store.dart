import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'regions.dart';

/// Everything needed to talk to the ThinQ API. The PAT lives only in the
/// platform secure storage, never in source code.
class ThinqCredentials {
  const ThinqCredentials({
    required this.pat,
    required this.country,
    required this.region,
    required this.clientId,
  });

  final String pat;
  final String country;
  final ThinqRegion region;
  final String clientId;
}

class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kPat = 'pat';
  static const _kCountry = 'country';
  static const _kRegion = 'region';
  static const _kClientId = 'clientId';
  static const _kTempStep = 'tempStep';
  static const _kThemeMode = 'themeMode';

  Future<ThinqCredentials?> load() async {
    try {
      final pat = await _storage.read(key: _kPat);
      if (pat == null || pat.isEmpty) return null;
      return ThinqCredentials(
        pat: pat,
        country: await _storage.read(key: _kCountry) ?? 'BR',
        region: ThinqRegion.fromName(await _storage.read(key: _kRegion)),
        clientId: await _clientId(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<ThinqCredentials> save({
    required String pat,
    required String country,
    required ThinqRegion region,
  }) async {
    await _storage.write(key: _kPat, value: pat);
    await _storage.write(key: _kCountry, value: country);
    await _storage.write(key: _kRegion, value: region.name);
    return ThinqCredentials(
      pat: pat,
      country: country,
      region: region,
      clientId: await _clientId(),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _kPat);
  }

  // Non-secret user preference. Kept here (not in a separate prefs plugin) so
  // it uses the storage that is already proven to work on every platform.
  Future<double?> loadTempStep() async {
    try {
      final raw = await _storage.read(key: _kTempStep);
      return raw == null ? null : double.tryParse(raw);
    } catch (e) {
      debugPrint('Falha ao ler o passo de temperatura: $e');
      return null;
    }
  }

  /// 'light' | 'dark'; null means "follow the system".
  Future<String?> loadThemeMode() async {
    try {
      return await _storage.read(key: _kThemeMode);
    } catch (e) {
      debugPrint('Falha ao ler o tema: $e');
      return null;
    }
  }

  Future<void> saveThemeMode(String mode) async {
    try {
      await _storage.write(key: _kThemeMode, value: mode);
    } catch (e) {
      debugPrint('Falha ao salvar o tema: $e');
    }
  }

  Future<void> saveTempStep(double step) async {
    try {
      await _storage.write(key: _kTempStep, value: step.toString());
    } catch (e) {
      debugPrint('Falha ao salvar o passo de temperatura: $e');
    }
  }

  /// A unique, persistent id for this installation (x-client-id header).
  Future<String> _clientId() async {
    var id = await _storage.read(key: _kClientId);
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      final hex = List.generate(
        16,
        (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      id = 'air-control-$hex';
      await _storage.write(key: _kClientId, value: id);
    }
    return id;
  }
}
