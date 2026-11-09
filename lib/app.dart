import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/providers.dart';
import 'ui/home/home_screen.dart';
import 'ui/setup/connect_screen.dart';
import 'ui/theme/app_theme.dart';

class AirControlApp extends ConsumerWidget {
  const AirControlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(credentialsProvider) != null;
    return MaterialApp(
      title: 'Air Control',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // All app text is Portuguese; this also localizes built-in widgets such
      // as the time picker ("OK" / "Cancelar").
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 350),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: signedIn
            ? const HomeScreen(key: ValueKey('home'))
            : const ConnectScreen(key: ValueKey('connect')),
      ),
    );
  }
}
