import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/front_surrounds/front_surrounds_flow.dart';
import 'features/home_theater/home_theater_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const DiscoveryScreen()),
    GoRoute(
      path: '/theater/:uuid',
      builder: (_, state) =>
          HomeTheaterScreen(soundbarUuid: state.pathParameters['uuid']!),
    ),
    GoRoute(
      path: '/theater/:uuid/fronts',
      builder: (_, state) =>
          FrontSurroundsFlow(soundbarUuid: state.pathParameters['uuid']!),
    ),
  ],
);

class SonorityApp extends StatelessWidget {
  const SonorityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp.router(
          title: 'Sonority',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(lightDynamic?.harmonized()),
          darkTheme: AppTheme.dark(darkDynamic?.harmonized()),
          themeMode: ThemeMode.system,
          routerConfig: _router,
        );
      },
    );
  }
}
