import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/front_surrounds/front_surrounds_flow.dart';
import 'features/home_theater/home_theater_screen.dart';
import 'features/profiles/profiles_screen.dart';
import 'features/profiles/profile_edit_screen.dart';
import 'features/room/room_screen.dart';
import 'features/stereo_pair/stereo_pair_flow.dart';

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
            GoRoute(
                path: '/stereo-pair',
                builder: (_, __) => const StereoPairFlow()),
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
                    path: 'new',
                    builder: (_, __) => const ProfileEditScreen(profileId: null)),
                GoRoute(
                  path: 'edit/:id',
                  builder: (_, s) =>
                      ProfileEditScreen(profileId: s.pathParameters['id']),
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
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
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
    );
  }
}

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
