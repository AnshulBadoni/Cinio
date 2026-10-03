import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/mode/content_mode.dart';
import '../../core/mode/content_mode_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/nav_prefs.dart';
import '../downloads/downloads_screen.dart';
import '../history/history_screen.dart';
import '../auth/auth_cubit.dart';
import '../home/home_screen.dart';
import '../home/my_list_screen.dart';
import '../home/search_screen.dart';
import '../schedule/schedule_screen.dart';
import '../settings/settings_screen.dart';
import '../../core/ui/dock_visibility.dart';
import 'desktop_shell.dart';
import 'root_shell_tv.dart';

/// The four pages used by both [RootShell] (phone bottom nav) and
/// [RootShellTv] (TV left rail). Any change to the page set must be
/// reflected in BOTH shells; this single function is the one source of truth.
///
/// [searchFocusSignal] is bumped each time the Search tab/rail-item is
/// (re)selected so the embedded search screen can auto-focus its field.
List<Widget> buildShellPages(ValueNotifier<int>? searchFocusSignal) => [
  const HomeScreen(),
  SearchScreen(showBack: false, focusSignal: searchFocusSignal),
  const MyListScreen(),
  const SettingsScreen(),
];

/// App-level navigation shell — five tabs via a custom floating dock
/// (frosted capsule hovering over the content; no Material NavigationBar).
///
/// Uses [IndexedStack] so each screen preserves its scroll/state when
/// the user switches tabs.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with TickerProviderStateMixin {
  /// The tab showing, by identity. Was an int index into a hardcoded five —
  /// which stopped meaning anything once the dock became reorderable.
  DockTab _tab = DockTab.home;

  /// Falls back to an unregistered instance rather than throwing.
  ///
  /// Production always registers it; widget tests build this shell with only
  /// the deps they care about. A bare [NavPrefs] reads no Hive box and returns
  /// [NavPrefs.defaultTabs], which is the dock those tests expect anyway —
  /// same guard the bloc uses for ContentModeCubit.
  late final NavPrefs _navPrefs =
      sl.isRegistered<NavPrefs>() ? sl<NavPrefs>() : NavPrefs();

  /// Double-back-to-exit: timestamp of the last root Back press. A second Back
  /// within 2s exits the app; the first just shows the "press back again" toast.
  DateTime? _lastBackPress;
  late final AnimationController _dockCtrl;

  /// Tab-switch entrance: the visible page swaps immediately and the INCOMING
  /// tab fades + slides up into place (200ms, ease-out). We never fade the old
  /// tab out to blank — that midpoint blank frame read as a stutter. The
  /// [IndexedStack] stays alive, so every tab keeps its scroll position and
  /// nothing is rebuilt during the animation (the page is a cached layer).
  late final AnimationController _switchCtrl;
  late final Animation<double> _switch;

  /// Bumped each time the Search tab is (re)selected so the search screen can
  /// auto-focus its field and pop the keyboard, without stealing focus while
  /// the tab sits idle in the [IndexedStack].
  final ValueNotifier<int> _searchFocusSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _dockCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 0,
    );
    _switchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _switch = CurvedAnimation(parent: _switchCtrl, curve: Curves.easeOutCubic);
    _navPrefs.addListener(_onTabsChanged);
  }

  /// The dock was edited in Settings. If the tab we're on just got hidden,
  /// land somewhere that still exists instead of showing a page with no item.
  void _onTabsChanged() {
    if (!mounted) return;
    final visible = _visibleTabs();
    setState(() {
      if (!visible.contains(_tab)) _tab = visible.first;
    });
  }

  /// The dock as actually rendered: the user's order, minus anything the
  /// current content mode has no use for.
  List<DockTab> _visibleTabs() {
    final mode = sl<ContentModeCubit>().state;
    final tabs = _navPrefs.tabs;
    if (!mode.isReading) return tabs;
    final out = [for (final t in tabs) if (!t.isAnimeOnly) t];
    return out.isEmpty ? tabs : out;
  }

  @override
  void dispose() {
    _navPrefs.removeListener(_onTabsChanged);
    _switchCtrl.dispose();
    _dockCtrl.dispose();
    _searchFocusSignal.dispose();
    super.dispose();
  }

  void _onTabSelected(DockTab tab) {
    if (tab == _tab) {
      // Re-tapping the current tab: no transition, just re-focus Search.
      if (tab == DockTab.search) _searchFocusSignal.value++;
      return;
    }
    setState(() => _tab = tab);
    if (tab == DockTab.search) _searchFocusSignal.value++;
    _switchCtrl.forward(from: 0);
  }

  /// Root-level Back: the first press shows a toast, a second within 2s exits.
  /// Only reached when Back would otherwise close the app — deep screens
  /// (detail, player, …) are pushed above this shell and pop normally.
  void _onBack() {
    // A sub-page inside the current tab (an open Settings section, an active
    // search) owns this Back — its own PopScope handles it in the same event.
    // Both PopScopes share this route, so Flutter fires ours too; bail so we
    // don't flash the exit toast over a normal in-tab back-out.
    if (shellBackIntercepted.value) return;
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    // FToast (part of fluttertoast) rather than the plain showToast, so the
    // pill can sit ABOVE the floating dock — showToast has no bottom offset.
    (FToast()..init(context)).showToast(
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 2),
      child: Container(
        margin: const EdgeInsets.only(bottom: 104),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xF01C1C1E),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Text(
          'Press BACK again to exit',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  /// One page per visible tab, in the same order the dock draws them, so the
  /// [IndexedStack] index is just the tab's position in that list.
  ///
  /// [buildShellPages] stays the shared Home/Search/My List/Settings set that
  /// the TV rail also builds from — untouched, so TV is unaffected.
  List<Widget> _pagesFor(List<DockTab> tabs) {
    final shared = buildShellPages(_searchFocusSignal);
    return [
      for (final t in tabs)
        switch (t) {
          DockTab.home => shared[0],
          DockTab.search => shared[1],
          DockTab.myList => shared[2],
          DockTab.profile => shared.last, // Settings, shown as "Profile"
          DockTab.schedule => const ScheduleScreen(),
          // Both normally get pushed with a back button; as tabs they own the
          // whole screen, so their own back affordance is suppressed.
          DockTab.downloads => const DownloadsScreen(showBack: false),
          DockTab.history => const HistoryScreen(showBack: false),
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) return const RootShellTv();
    if (sl<AppMode>().isDesktop) return const DesktopShell();
    // Reading modes have no Schedule tab (it's omitted from the dock below).
    // If the mode flips to Manga/Novel while Schedule (tab 1) is showing,
    // bounce back to Home rather than leaving the user on a tab that no
    // longer has a dock item.
    return PopScope(
      // Intercept Back at the app root: first press toasts, second exits.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: BlocListener<ContentModeCubit, ContentMode>(
        bloc: sl<ContentModeCubit>(),
        listenWhen: (prev, curr) => prev != curr,
        listener: (context, mode) {
          // Always rebuild: the dock's items are computed in build() now, so
          // the mode change has to reach it. (The Row used to sit inside its
          // own BlocBuilder; the tab list replaced that.) Schedule is dropped
          // in reading modes, so if that's where we were, land on the first
          // tab that survives rather than on a page with no dock item.
          setState(() {
            if (mode.isReading && _tab.isAnimeOnly) {
              _tab = _visibleTabs().first;
            }
          });
        },
        child: Scaffold(
          backgroundColor: AppColors.bg,
          // Content runs under the floating dock (screens keep their own bottom
          // padding so the last row scrolls clear of it).
          extendBody: true,
          body: Builder(builder: (context) {
            final visible = _visibleTabs();
            final active = visible.indexOf(_tab);
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Follow real vertical finger movement. A downward scroll
                // collapses the dock; an upward scroll expands it. Crucially,
                // an upward overscroll while the scroll position is already at
                // the top is ignored, so the dock never flashes large→small at
                // the top edge of a page.
                if (notification.metrics.axis == Axis.vertical &&
                    notification is ScrollUpdateNotification) {
                  final delta = notification.scrollDelta ?? 0.0;
                  final pixels = notification.metrics.pixels;

                  if (pixels <= 0) {
                    // At top / overscroll area: always remain fully expanded
                    if (_dockCtrl.value != 0) _dockCtrl.value = 0;
                  } else if (delta > 0.4) {
                    // Scrolling down (content moving up): collapse dock
                    _dockCtrl.value = math.min(
                      1.0,
                      _dockCtrl.value + delta / 240.0,
                    );
                  } else if (delta < -0.4) {
                    // Scrolling up (content moving down): expand dock
                    _dockCtrl.value = math.max(
                      0.0,
                      _dockCtrl.value + delta / 240.0,
                    );
                  }
                }
                return false;
              },
              child: AnimatedBuilder(
                animation: _switch,
                builder: (context, child) {
              final v = _switch.value;
              // Incoming tab fades in from 0.4 and slides up 20px. Never blanks.
              return Opacity(
                opacity: 0.4 + 0.6 * v,
                child: Transform.translate(
                  offset: Offset(0, (1 - v) * 20),
                  child: child,
                ),
              );
            },
                // RepaintBoundary → the page is a single cached layer the transition
                // just composites (opacity + translate), so no repaint per frame.
                child: RepaintBoundary(
              child: IndexedStack(
                // indexOf can be -1 for one frame if the mode flipped before
                // the listener ran; clamp rather than throw.
                index: active < 0 ? 0 : active,
                children: _pagesFor(visible),
              ),
                ),
              ),
            );
          }),
          bottomNavigationBar: ValueListenableBuilder<bool>(
            valueListenable: dockHiddenBySection,
            builder: (context, sectionOpen, _) {
              // Slide the dock away only when a Settings section is open AND the
              // Settings (Profile, last) tab is the one showing — every other tab
              // keeps its dock.
              final hide = sectionOpen && _tab == DockTab.profile;
              return AnimatedSlide(
                offset: hide ? const Offset(0, 1.6) : Offset.zero,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: IgnorePointer(
                  ignoring: hide,
                  child: _FloatingDock(
                    tabs: _visibleTabs(),
                    active: _tab,
                    collapse: _dockCtrl,
                    onSelected: _onTabSelected,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

BoxDecoration _dockDecoration({
  required double radius,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    color: const Color(0x99101014), // ~60% dark tint so underlying artwork softly shows through
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.12),
      width: 0.65,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

/// The frosted floating capsule: single Gaussian blur glass layer, hairline border,
/// exactly four items (Home, Search, Download, Library) and a compact detached Profile
/// circle with avatar filling ~82%.
class _FloatingDock extends StatelessWidget {
  const _FloatingDock({
    required this.tabs,
    required this.active,
    required this.collapse,
    required this.onSelected,
  });

  final List<DockTab> tabs;
  final DockTab active;
  final Animation<double> collapse;
  final ValueChanged<DockTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return AnimatedBuilder(
      animation: collapse,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(
          collapse.value.clamp(0.0, 1.0),
        );
        final navPrefs = sl.isRegistered<NavPrefs>() ? sl<NavPrefs>() : null;
        final separateProfile = navPrefs?.separateProfile ?? true;
        final hasProfile = tabs.contains(DockTab.profile);
        final isSplit = separateProfile && hasProfile;

        // Proportions: compact and balanced (58dp expanded -> 44dp collapsed)
        final height = 58.0 - (14.0 * t);
        final radius = height / 2;

        final expandedWidth = (screenWidth * 0.90).clamp(290.0, 480.0);
        final compactWidth = (screenWidth * 0.66).clamp(230.0, 360.0);
        final totalWidth = expandedWidth + (compactWidth - expandedWidth) * t;

        Widget buildCapsuleContent(List<DockTab> pillTabs) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in pillTabs)
                Expanded(
                  child: _DockItem(
                    tab: tab,
                    selected: active == tab,
                    onTap: () => onSelected(tab),
                    collapse: collapse,
                  ),
                ),
            ],
          );
        }

        Widget buildPillContainer({
          required double pillWidth,
          required List<DockTab> pillTabs,
        }) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                width: pillWidth,
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: _dockDecoration(radius: radius),
                child: buildCapsuleContent(pillTabs),
              ),
            ),
          );
        }

        Widget content;
        if (isSplit) {
          final mainTabs = tabs.where((t) => t != DockTab.profile).toList();
          final circleSize = height;
          const gap = 10.0;
          final mainWidth = totalWidth - circleSize - gap;

          content = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              buildPillContainer(
                pillWidth: mainWidth,
                pillTabs: mainTabs,
              ),
              const SizedBox(width: gap),
              _ProfileCircle(
                size: circleSize,
                radius: radius,
                selected: active == DockTab.profile,
                onTap: () => onSelected(DockTab.profile),
              ),
            ],
          );
        } else {
          content = buildPillContainer(
            pillWidth: totalWidth,
            pillTabs: tabs,
          );
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: bottomInset > 0 ? bottomInset + 4 : 12.0,
            ),
            child: content,
          ),
        );
      },
    );
  }
}

class _ProfileCircle extends StatelessWidget {
  const _ProfileCircle({
    required this.size,
    required this.radius,
    required this.selected,
    required this.onTap,
  });

  final double size;
  final double radius;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // User avatar fills ~82% of the circle, leaving a clean minimal frosted rim
    final avatarSize = (size * 0.82).roundToDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: size,
          height: size,
          decoration: _dockDecoration(radius: radius),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: Center(
                child: _DockPop(
                  selected: selected,
                  child: BlocBuilder<AuthCubit, AuthState>(
                    builder: (context, auth) {
                      if (auth.isLoggedIn && auth.avatarUrl != null) {
                        return Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.20),
                              width: selected ? 1.5 : 0.8,
                            ),
                            image: DecorationImage(
                              image: NetworkImage(auth.avatarUrl!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      }
                      final activeAccent = AppColors.accent;
                      return Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? activeAccent.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: selected
                                ? activeAccent
                                : Colors.white.withValues(alpha: 0.20),
                            width: selected ? 1.4 : 0.8,
                          ),
                        ),
                        child: Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedUserCircle02,
                            color: selected
                                ? Color.lerp(Colors.white, activeAccent, 0.28)!
                                : const Color(0xFF9E9EA6),
                            size: avatarSize * 0.58,
                            strokeWidth: selected ? 2.0 : 1.6,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<List<dynamic>> _hugeIconFor(DockTab t) => switch (t) {
  DockTab.home => HugeIcons.strokeRoundedHome04,
  DockTab.search => HugeIcons.strokeRoundedSearch01,
  DockTab.downloads => HugeIcons.strokeRoundedDownload03,
  DockTab.myList => HugeIcons.strokeRoundedFolderLibrary,
  DockTab.schedule => HugeIcons.strokeRoundedCalendar03,
  DockTab.history => HugeIcons.strokeRoundedClock01,
  DockTab.profile => HugeIcons.strokeRoundedUserCircle02,
};

class _DockPop extends StatelessWidget {
  const _DockPop({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(selected),
      tween: Tween(begin: selected ? 0.90 : 1.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: child,
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.collapse,
  });

  final DockTab tab;
  final bool selected;
  final VoidCallback onTap;
  final Animation<double> collapse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: collapse,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(
          collapse.value.clamp(0.0, 1.0),
        );
        final labelOpacity = (1.0 - t * 2.2).clamp(0.0, 1.0);
        final labelHeight = 13.5 * (1.0 - t);
        final activeAccent = AppColors.accent;
        final itemColor = selected
            ? Color.lerp(Colors.white, activeAccent, 0.28)!
            : const Color(0xFF9E9EA6);
        final label = tab.label;

        final Widget iconWidget = HugeIcon(
          icon: _hugeIconFor(tab),
          color: itemColor,
          size: 21.2,
          strokeWidth: selected ? 2.1 : 1.6,
        );

        final navPrefs = sl.isRegistered<NavPrefs>() ? sl<NavPrefs>() : null;
        final showLabels = navPrefs?.showNavigationLabels ?? true;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(
                  horizontal: 2.0,
                  vertical: 2.0,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                decoration: BoxDecoration(
                  color: selected
                      ? activeAccent.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 23,
                        child: Center(
                          child: _DockPop(selected: selected, child: iconWidget),
                        ),
                      ),
                      if (showLabels && labelOpacity > 0.01) ...[
                        SizedBox(height: 1.5 * (1.0 - t)),
                        SizedBox(
                          height: labelHeight,
                          child: Opacity(
                            opacity: labelOpacity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11.0,
                                  color: itemColor,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
