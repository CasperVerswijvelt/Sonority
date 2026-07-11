import 'package:animations/animations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'demo/demo_mode.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/front_surrounds/front_surrounds_flow.dart';
import 'features/home_theater/home_theater_screen.dart';
import 'features/profiles/profile_controller.dart';
import 'features/profiles/profile_shortcuts.dart';
import 'features/profiles/profile_widget.dart';
import 'features/profiles/profiles_screen.dart';
import 'features/profiles/profile_create_screen.dart';
import 'features/profiles/profile_detail_screen.dart';
import 'features/room/room_screen.dart';
import 'features/group/group_flow.dart';
import 'features/group/group_detail_screen.dart';

/// Root navigator key — lets an out-of-app launch (app shortcut / widget) reach
/// a BuildContext to run the apply flow even when no widget context is handy.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute(
      builder: (context, state, shell) => _HomeShell(shell: shell),
      navigatorContainerBuilder: (context, shell, children) =>
          _AnimatedBranchContainer(
        currentIndex: shell.currentIndex,
        children: children,
      ),
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
                  // Nested so the stack is [overview, detail, resnapshot] —
                  // Back returns to the detail page, declaratively (no push).
                  routes: [
                    GoRoute(
                      path: 'resnapshot',
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
        // Foreground: the nav bar's opaque background would paint over a
        // background-position border, so draw the line on top of its top edge.
        position: DecorationPosition.foreground,
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

/// Renders the shell's branch navigators, cross-animating the active branch
/// with an M3 shared-axis transition on tab switch. All branches stay mounted
/// (Offstage) so each tab keeps its state, exactly like the old IndexedStack.
class _AnimatedBranchContainer extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;
  const _AnimatedBranchContainer({
    required this.currentIndex,
    required this.children,
  });

  @override
  State<_AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<_AnimatedBranchContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1, // start settled; only tab changes drive it
  );
  int _previousIndex = 0;
  bool _reverse = false;

  @override
  void didUpdateWidget(_AnimatedBranchContainer old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _previousIndex = old.currentIndex;
      // Slide the way the tab bar moves: forward to a higher index, back to a lower.
      _reverse = widget.currentIndex < old.currentIndex;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final animating = _controller.isAnimating;
        // Draw non-active branches first, active branch last so it paints on top.
        final ordered = <Widget>[];
        for (var i = 0; i < widget.children.length; i++) {
          if (i == widget.currentIndex) continue;
          ordered.add(_branch(
            widget.children[i],
            visible: animating && i == _previousIndex,
            outgoing: true,
          ));
        }
        ordered.add(_branch(
          widget.children[widget.currentIndex],
          visible: true,
          outgoing: false,
        ));
        return Stack(children: ordered);
      },
    );
  }

  Widget _branch(Widget child, {required bool visible, required bool outgoing}) {
    if (!visible) {
      return Offstage(
        offstage: true,
        child: TickerMode(enabled: false, child: child),
      );
    }
    // Forward: new slides in from the right, old exits left. Reverse mirrors it
    // by driving the transitions backwards (ReverseAnimation), so back-navigation
    // slides the opposite way.
    final rev = ReverseAnimation(_controller);
    return SharedAxisTransition(
      animation: outgoing
          ? (_reverse ? rev : kAlwaysCompleteAnimation)
          : (_reverse ? kAlwaysCompleteAnimation : _controller),
      secondaryAnimation: outgoing
          ? (_reverse ? kAlwaysDismissedAnimation : _controller)
          : (_reverse ? rev : kAlwaysDismissedAnimation),
      transitionType: SharedAxisTransitionType.horizontal,
      fillColor: Colors.transparent,
      child: child,
    );
  }
}

class SonorityApp extends ConsumerStatefulWidget {
  const SonorityApp({super.key});

  @override
  ConsumerState<SonorityApp> createState() => _SonorityAppState();
}

class _SonorityAppState extends ConsumerState<SonorityApp> {
  @override
  void initState() {
    super.initState();
    // App-icon shortcut tap → funnel through pendingApplyProvider (also fires
    // for the shortcut that cold-started the app).
    initProfileShortcuts(
        (id) => ref.read(pendingApplyProvider.notifier).set(id));
    // Home-screen widget tap → same apply seam.
    initProfileWidget((id) => ref.read(pendingApplyProvider.notifier).set(id));
  }

  /// Runs the scan→preflight→apply flow for a launch-requested profile. Deferred
  /// to the next frame so the navigator exists even on a cold-start shortcut.
  void _consumePending(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      ref.read(pendingApplyProvider.notifier).set(null);
      _router.go('/profiles');
      final profiles = await ref.read(profilesProvider.future);
      final matches = profiles.where((p) => p.id == id);
      if (matches.isEmpty || !ctx.mounted) return;
      await applyProfileFromLaunch(ctx, ref, matches.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    // One top-level listener drives every out-of-app apply.
    ref.listen(pendingApplyProvider, (_, next) {
      if (next != null) _consumePending(next);
    });
    // Keep the OS shortcut list + the iOS widget's profile list in sync.
    ref.listen(profilesProvider, (_, next) {
      final list = next.value;
      if (list != null) {
        syncProfileShortcuts(list);
        publishWidgetProfiles(list);
      }
    });

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Material You only on Android. On macOS `dynamic_color` returns the
        // system accent (not Material You), which would diverge from Android —
        // so Apple platforms ignore it and use our fixed seed instead.
        final useDynamic =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        // The screenshot-only web build renders on desktop Chrome, which
        // reports a desktop platform — so ReorderableListView shows drag
        // handles and scrollbars appear. Pose as iOS there so the captured
        // screens look like the mobile app. (Can't use
        // debugDefaultTargetPlatformOverride — it throws in release builds.)
        final platform =
            (kDemoMode && kIsWeb) ? TargetPlatform.iOS : null;
        return MaterialApp.router(
          title: 'Sonority',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(useDynamic ? lightDynamic?.harmonized() : null)
              .copyWith(platform: platform),
          darkTheme:
              AppTheme.dark(useDynamic ? darkDynamic?.harmonized() : null)
                  .copyWith(platform: platform),
          themeMode: ThemeMode.system,
          routerConfig: _router,
          // The screenshot-only web demo build has no OS status bar / home
          // indicator, so inject small safe insets purely as framing margin
          // (see docs/MARKETING-ASSETS.md §2). Less top/bottom than a real
          // device (no bars to clear); a little left/right so cards don't hug
          // the phone frame. app_scaffold's body SafeArea turns bottom/left/
          // right into margins; the AppBar consumes top. Native is untouched.
          builder: (kDemoMode && kIsWeb)
              ? (context, child) {
                  const inset = EdgeInsets.fromLTRB(16, 16, 16, 12);
                  final mq = MediaQuery.of(context);
                  return MediaQuery(
                    data: mq.copyWith(
                      padding: mq.padding + inset,
                      viewPadding: mq.viewPadding + inset,
                    ),
                    child: child!,
                  );
                }
              : null,
        );
      },
    );
  }
}
