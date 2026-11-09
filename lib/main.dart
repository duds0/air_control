import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/secure_store.dart';
import 'domain/providers.dart';
import 'widget/ac_widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(440, 840),
        minimumSize: Size(380, 640),
        center: true,
        title: 'Air Control',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  await AcWidgetService.init(); // home-screen widget taps (Android)

  final store = SecureStore();
  final creds = await store.load();
  final tempStep = await store.loadTempStep();
  final themeMode = ThemeModeNotifier.parse(await store.loadThemeMode());
  runApp(
    ProviderScope(
      overrides: [
        initialCredentialsProvider.overrideWithValue(creds),
        initialTempStepProvider.overrideWithValue(tempStep),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const AirControlApp(),
    ),
  );
}
