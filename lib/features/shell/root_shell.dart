import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
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
    with SingleTickerProviderStateMixin {
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
                      _dockCtrl.value + delta / 85.0,
                    );
                  } else if (delta < -0.4) {
                    // Scrolling up (content moving down): expand dock
                    _dockCtrl.value = math.max(
                      0.0,
                      _dockCtrl.value + delta / 85.0,
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

/// The frosted floating capsule: blurred surface, hairline border, five
/// items. Active tab = the icon's solid accent twin + accent label — the
/// state change lives in the icon itself (deliberately not the Material
/// pill/indicator look).
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
        // The dock morphs as one coherent object: it gets narrower and
        // shorter while labels disappear. Every item keeps an equal column,
        // so the glass never becomes a collection of unrelated buttons.
        final t = Curves.easeOutCubic.transform(
          collapse.value.clamp(0.0, 1.0),
        );
        final expandedWidth = (screenWidth * 0.90).clamp(300.0, 520.0);
        final compactWidth = (screenWidth * 0.64).clamp(240.0, 360.0);
        final width = expandedWidth + (compactWidth - expandedWidth) * t;
        final height = 74.0 - (16.0 * t);
        final radius = height / 2;

        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset + 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  width: width,
                  height: height,
                  padding: EdgeInsets.all(5.0 - (1.0 * t)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    color: const Color(0xEE131317),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 0.75,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, -1),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // A single glass highlight belongs to the surface, not
                      // to individual buttons. This keeps every tab uniform.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(radius - 5),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.09),
                                  Colors.white.withValues(alpha: 0.01),
                                ],
                                stops: const [0.0, 0.48],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final tab in tabs)
                            Expanded(
                              child: _DockItem(
                                label: tab == DockTab.profile ? 'Profile' : tab.label,
                                icon: tab == DockTab.profile
                                    ? null
                                    : _iconFor(tab),
                                profile: tab == DockTab.profile,
                                selected: active == tab,
                                onTap: () => onSelected(tab),
                                collapse: collapse,
                              ),
                            ),
                        ],
                      ),
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

(IconData, IconData)? _iconFor(DockTab t) => switch (t) {
  DockTab.home => (CupertinoIcons.house, CupertinoIcons.house_fill),
  DockTab.search => (CupertinoIcons.compass, CupertinoIcons.compass_fill),
  DockTab.myList => (CupertinoIcons.bookmark, CupertinoIcons.bookmark_fill),
  DockTab.schedule => (CupertinoIcons.calendar, CupertinoIcons.calendar_today),
  DockTab.downloads => (CupertinoIcons.arrow_down_circle, CupertinoIcons.arrow_down_circle_fill),
  DockTab.history => (CupertinoIcons.clock, CupertinoIcons.clock_fill),
  _ => null,
};

class _DockPop extends StatelessWidget {
  const _DockPop({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(selected),
      tween: Tween(begin: selected ? 0.88 : 1.0, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: child,
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.label,
    required this.icon,
    required this.profile,
    required this.selected,
    required this.onTap,
    required this.collapse,
  });

  final String label;
  final (IconData, IconData)? icon;
  final bool profile;
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
        final labelOpacity = 1.0 - t;
        final iconColor = selected ? AppColors.accent : const Color(0xFFD4D4D8);

        Widget iconWidget;
        if (profile) {
          iconWidget = BlocBuilder<AuthCubit, AuthState>(
            builder: (context, auth) {
              if (auth.isLoggedIn && auth.avatarUrl != null) {
                return Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.accent.withValues(alpha: 0.92)
                          : Colors.white.withValues(alpha: 0.28),
                      width: 1.2,
                    ),
                    image: DecorationImage(
                      image: NetworkImage(auth.avatarUrl!),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              }
              return Icon(
                selected
                    ? CupertinoIcons.person_crop_circle_fill
                    : CupertinoIcons.person_crop_circle,
                color: iconColor,
                size: 21,
              );
            },
          );
        } else {
          iconWidget = Icon(
            selected ? icon!.$2 : icon!.$1,
            color: iconColor,
            size: 21,
          );
        }

        final isCompact = t > 0.45;
        const circleSize = 38.0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: isCompact ? circleSize : double.infinity,
                height: isCompact ? circleSize : null,
                margin: EdgeInsets.symmetric(
                  horizontal: isCompact ? 0 : 3.0,
                  vertical: isCompact ? 0 : 2.0,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 0 : 4.0,
                  vertical: isCompact ? 0 : 4.0,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                  shape: isCompact ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isCompact ? null : BorderRadius.circular(999),
                  border: selected
                      ? Border.all(
                          color: AppColors.accent.withValues(alpha: 0.35),
                          width: 0.75,
                        )
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 24,
                      child: Center(
                        child: _DockPop(selected: selected, child: iconWidget),
                      ),
                    ),
                    if (t < 0.92)
                      SizedBox(
                        height: 14.0 * (1.0 - t),
                        child: ClipRect(
                          child: Opacity(
                            opacity: labelOpacity.clamp(0.0, 1.0),
                            child: Center(
                              child: Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1,
                                  color: iconColor,
                                  fontWeight:
                                      selected ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
