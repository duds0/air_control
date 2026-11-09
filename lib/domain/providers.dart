import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/regions.dart';
import '../core/secure_store.dart';
import '../data/thinq_repository.dart';
import '../widget/ac_widget_service.dart';

final secureStoreProvider = Provider<SecureStore>((_) => SecureStore());

/// Credentials loaded at startup in main(); overridden there.
final initialCredentialsProvider = Provider<ThinqCredentials?>((_) => null);

class CredentialsNotifier extends Notifier<ThinqCredentials?> {
  @override
  ThinqCredentials? build() => ref.read(initialCredentialsProvider);

  /// Saves the PAT, validates it against the API and signs in.
  /// Throws if the token is rejected.
  Future<void> signIn({
    required String pat,
    required String country,
    required ThinqRegion region,
  }) async {
    final store = ref.read(secureStoreProvider);
    final creds = await store.save(
      pat: pat.trim(),
      country: country.trim().toUpperCase(),
      region: region,
    );
    try {
      await ThinqRepository(ThinqApiClient(creds)).devices();
    } catch (_) {
      await store.clear();
      rethrow;
    }
    state = creds;
  }

  Future<void> signOut() async {
    await ref.read(secureStoreProvider).clear();
    await AcWidgetService.clear();
    state = null;
  }
}

final credentialsProvider =
    NotifierProvider<CredentialsNotifier, ThinqCredentials?>(
  CredentialsNotifier.new,
);

/// Temperature increment chosen by the user (e.g. 0.5 or 1.0), persisted.
/// Loaded in main(); null means "use the device's own step".
final initialTempStepProvider = Provider<double?>((_) => null);

class TempStepNotifier extends Notifier<double?> {
  @override
  double? build() => ref.read(initialTempStepProvider);

  Future<void> set(double step) async {
    state = step; // instant in the UI; persisting happens in the background
    await ref.read(secureStoreProvider).saveTempStep(step);
  }
}

final tempStepProvider =
    NotifierProvider<TempStepNotifier, double?>(TempStepNotifier.new);

/// Light/dark choice, persisted. Starts as "follow the system" until the user
/// picks one with the top-bar button. Loaded in main().
final initialThemeModeProvider = Provider<ThemeMode>((_) => ThemeMode.system);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  /// Switches to the opposite of what is currently on screen.
  Future<void> toggle(Brightness current) {
    final next = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    return ref.read(secureStoreProvider).saveThemeMode(next.name);
  }

  static ThemeMode parse(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

final repositoryProvider = Provider<ThinqRepository?>((ref) {
  final creds = ref.watch(credentialsProvider);
  return creds == null ? null : ThinqRepository(ThinqApiClient(creds));
});
