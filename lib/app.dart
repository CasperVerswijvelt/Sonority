import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/front_surrounds/front_surrounds_flow.dart';
import 'features/home_theater/home_theater_screen.dart';
import 'features/profiles/profiles_screen.dart';
import 'features/profiles/profile_create_screen.dart';
import 'features/profiles/profile_detail_screen.dart';
import 'features/room/room_screen.dart';
import 'features/group/group_flow.dart';
import 'features/group/group_detail_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _HomeShell(shell: shell),
      branches: [
        // System: discovery + the per-device detail/flow screens.
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (_, __) => const DiscoveryScreen()),
            GoRoute(path: '/group', builder: (_, __) => const GroupFlow()),
            GoRoute(
              path: '/group/:uuid',
              builder: (_, s) =>
                  GroupDetailScreen(uuid: s.pathParameters['uuid']!),
            ),
            GoRoute(
              path: '/room/:uuid',
              builder: (_, s) => RoomScreen(uuid: s.pathParameters['uuid']!),
            ),
            GoRoute(
              path: '/theater/:uuid',
              builder: (_, s) =>
                  HomeTheaterScreen(soundbarUuid: s.pathParameters['uuid']!),
            ),
            GoRoute(
              path: '/theater/:uuid/fronts',
              builder: (_, s) =>
                  FrontSurroundsFlow(soundbarUuid: s.pathParameters['uuid']!),
            ),
          ],
        ),
        // Profiles: list + create/edit.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profiles',
              builder: (_, __) => const ProfilesScreen(),
              routes: [
                GoRoute(
                    path: 'new', builder: (_, __) => const ProfileCreateScreen()),
                GoRoute(
                  path: 'edit/:id',
                  builder: (_, s) =>
                      ProfileDetailScreen(profileId: s.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'resnapshot/:id',
                  builder: (_, s) =>
                      ProfileCreateScreen(profileId: s.pathParameters['id']),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Root scaffold with the bottom tab bar switching between System and Profiles.
class _HomeShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const _HomeShell({required this.shell});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        // Hairline divider so the nav bar reads as a separate surface from the
        // page behind it (dynamic-colour tones alone don't separate them).
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.speaker_group_outlined),
                selectedIcon: Icon(Icons.speaker_group),
                label: 'System'),
            NavigationDestination(
                icon: Icon(Icons.dashboard_customize_outlined),
                selectedIcon: Icon(Icons.dashboard_customize),
                label: 'Profiles'),
          ],
        ),
      ),
    );
  }
}

class SonorityApp extends StatelessWidget {
  const SonorityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Material You only on Android. On macOS `dynamic_color` returns the
        // system accent (not Material You), which would diverge from Android —
        // so Apple platforms ignore it and use our fixed seed instead.
        final useDynamic = Platform.isAndroid;
        return MaterialApp.router(
          title: 'Sonority',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(useDynamic ? lightDynamic?.harmonized() : null),
          darkTheme:
              AppTheme.dark(useDynamic ? darkDynamic?.harmonized() : null),
          themeMode: ThemeMode.system,
          routerConfig: _router,
        );
      },
    );
  }
}
