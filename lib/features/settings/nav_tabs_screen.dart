import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/nav_prefs.dart';
import '../../core/ui/settings_widgets.dart';
import 'package:hugeicons/hugeicons.dart';

/// Choose which tabs the bottom bar shows, and in what order.
///
/// Laid out like `PlayerControlsScreen` — a live miniature on top, then the
/// lists — for the same reason: editing a list of names and guessing what the
/// bar ends up looking like is the part that doesn't work.
class NavTabsScreen extends StatefulWidget {
  const NavTabsScreen({super.key});

  @override
  State<NavTabsScreen> createState() => _NavTabsScreenState();
}

class _NavTabsScreenState extends State<NavTabsScreen> {
  NavPrefs get _prefs => sl<NavPrefs>();

  late List<DockTab> _shown = List.of(_prefs.tabs);

  List<DockTab> get _hidden =>
      [for (final t in DockTab.values) if (!_shown.contains(t)) t];

  bool get _canRemove => _shown.length > NavPrefs.minTabs;
  bool get _canAdd => _shown.length < NavPrefs.maxTabs;

  Future<void> _save() => _prefs.setTabs(_shown);

  void _remove(DockTab t) {
    if (t.isPinned || !_canRemove) return;
    setState(() => _shown.remove(t));
    _save();
  }

  void _add(DockTab t) {
    if (!_canAdd) return;
    // Insert before the pinned tab so Profile stays at the end, where the
    // thumb expects it.
    final pinnedAt = _shown.indexWhere((x) => x.isPinned);
    setState(() => _shown.insert(pinnedAt < 0 ? _shown.length : pinnedAt, t));
    _save();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final t = _shown.removeAt(oldIndex);
      _shown.insert(newIndex, t);
    });
    _save();
  }

  Future<void> _reset() async {
    await _prefs.reset();
    if (!mounted) return;
    setState(() => _shown = List.of(_prefs.tabs));
  }

  @override
  Widget build(BuildContext context) {
    final hidden = _hidden;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        'Navigation bar',
        actions: [
          TextButton(
            onPressed: _prefs.isDefault ? null : _reset,
            child: Text(
              'Reset',
              style: AppText.button.copyWith(
                color: _prefs.isDefault
                    ? AppColors.textTertiary
                    : AppColors.accent,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _preview(),
          const SizedBox(height: 4),
          SettingsSectionLabel(
            // The cap is visible before you hit it, rather than discovered as
            // a greyed-out button.
            'On the bar · ${_shown.length}/${NavPrefs.maxTabs}',
            first: true,
          ),
          SettingsCard(
            children: [
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: _reorder,
                children: [
                  for (var i = 0; i < _shown.length; i++)
                    _row(_shown[i], index: i),
                ],
              ),
            ],
          ),
          const SettingsSectionLabel('Not shown'),
          SettingsCard(
            children: hidden.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          'Every tab is on the bar.',
                          style: AppText.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ]
                : [for (final t in hidden) _row(t)],
          ),
          const SettingsSectionLabel('Style & blur'),
          SettingsCard(
            children: [
              _switchTile(
                icon: Icons.account_circle_outlined,
                title: 'Separate Profile circle',
                subtitle: 'Detach Profile as a floating circle (Material You)',
                value: _prefs.separateProfile,
                onChanged: (v) async {
                  await _prefs.setSeparateProfile(v);
                  if (mounted) setState(() {});
                },
              ),
              _switchTile(
                icon: Icons.lens_blur_rounded,
                title: 'Frosted glass navbar',
                subtitle: 'Translucent Gaussian blur with glass highlight',
                value: _prefs.frostedGlass,
                onChanged: (v) async {
                  await _prefs.setFrostedGlass(v);
                  if (mounted) setState(() {});
                },
              ),
              _switchTile(
                icon: Icons.label_outline_rounded,
                title: 'Show tab labels',
                subtitle: 'Show text below bottom navigation icons',
                value: _prefs.showNavigationLabels,
                onChanged: (v) async {
                  await _prefs.setShowNavigationLabels(v);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
            child: Text(
              'Drag to reorder. ${NavPrefs.minTabs}–${NavPrefs.maxTabs} tabs '
              'fit on the bar.\n\n'
              'Profile is pinned because it is the only way into Settings — '
              'hiding it would leave no way back to this screen. Schedule only '
              'appears in Streaming mode; there is no airing schedule to show '
              'while you are reading.',
              style: AppText.caption.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) {
    Future<void> flip(bool v) async {
      await onChanged(v);
      if (mounted) setState(() {});
    }

    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => flip(!value),
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: AppColors.accent,
        onChanged: flip,
      ),
    );
  }

  /// The dock as it will actually look — same frosted capsule, same glyphs,
  /// same outline→fill active state, redrawn as you edit.
  Widget _preview() {
    final separate = _prefs.separateProfile && _shown.contains(DockTab.profile);
    final frosted = _prefs.frostedGlass;
    final showLabels = _prefs.showNavigationLabels;
    final mainTabs = separate
        ? _shown.where((t) => t != DockTab.profile).toList()
        : _shown;
    final blurSigma = frosted ? 16.0 : 8.0;
    final bgColor = frosted
        ? const Color(0x7A121217)
        : const Color(0xEE131317);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 106,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B3350), Color(0xFF4A3450), Color(0xFF233042)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: frosted ? 0.16 : 0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                for (var i = 0; i < mainTabs.length; i++)
                                  Expanded(child: _previewItem(mainTabs[i], i == 0, showLabels)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (separate) ...[
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: bgColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: frosted ? 0.16 : 0.08),
                              ),
                            ),
                            child: Center(
                              child: HugeIcon(
                                icon: HugeIcons.strokeRoundedUserCircle02,
                                color: AppColors.textSecondary,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewItem(DockTab t, bool active, bool showLabels) {
    final color = active ? AppColors.accent : AppColors.textSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 19,
          child: Center(
            child: HugeIcon(
              icon: _hugeIconFor(t),
              color: color,
              size: 17,
              strokeWidth: active ? 2.1 : 1.6,
            ),
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: 2),
          Text(
            t.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 0.1,
              color: color,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

  static List<List<dynamic>> _hugeIconFor(DockTab t) => switch (t) {
    DockTab.home => HugeIcons.strokeRoundedHome04,
    DockTab.search => HugeIcons.strokeRoundedDiscoverCircle,
    DockTab.myList => HugeIcons.strokeRoundedFolderLibrary,
    DockTab.downloads => HugeIcons.strokeRoundedDownload03,
    DockTab.schedule => HugeIcons.strokeRoundedCalendar03,
    DockTab.history => HugeIcons.strokeRoundedClock01,
    DockTab.profile => HugeIcons.strokeRoundedUserCircle02,
  };

  Widget _row(DockTab t, {int? index}) {
    final onBar = index != null;
    final tint = onBar ? AppColors.textPrimary : AppColors.textTertiary;
    return Padding(
      key: ValueKey('${onBar ? 'on' : 'off'}_${t.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          if (onBar)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 19,
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            const SizedBox(width: 29),
          SizedBox(
            width: 22,
            child: Center(
              child: HugeIcon(
                icon: _hugeIconFor(t),
                color: tint,
                size: 19,
                strokeWidth: 1.7,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t.label,
              style: AppText.body.copyWith(color: tint, fontSize: 14.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (t.isAnimeOnly)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Streaming only',
                style: AppText.caption.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 11.5,
                ),
              ),
            ),
          if (t.isPinned)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'Pinned',
                style: AppText.caption.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 11.5,
                ),
              ),
            )
          else
            _action(t, onBar),
        ],
      ),
    );
  }

  Widget _action(DockTab t, bool onBar) {
    final enabled = onBar ? _canRemove : _canAdd;
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: onBar
          ? (enabled ? 'Remove' : 'Keep at least ${NavPrefs.minTabs} tabs')
          : (enabled ? 'Add' : 'The bar is full'),
      icon: Icon(
        onBar
            ? Icons.remove_circle_outline_rounded
            : Icons.add_circle_outline_rounded,
        size: 20,
        color: enabled
            ? (onBar ? AppColors.textSecondary : AppColors.accent)
            : AppColors.textTertiary.withValues(alpha: 0.35),
      ),
      onPressed:
          enabled ? () => onBar ? _remove(t) : _add(t) : null,
    );
  }
}
