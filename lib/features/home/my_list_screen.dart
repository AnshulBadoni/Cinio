import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/mode/content_mode.dart';
import '../../core/mode/content_mode_cubit.dart';
import '../../core/models/media_item.dart';
import '../../core/models/watch_status.dart';
import '../../core/playback/list_status_store.dart';
import '../../core/anilist/anilist_service.dart';
import '../../core/playback/category_store.dart';
import '../../core/ui/reveal_item.dart';
import '../../core/ui/global_messenger.dart';
import '../../core/ui/anilist_custom_lists_sheet.dart';
import '../../core/prefs/list_sort.dart';
import '../../core/models/provider_info.dart';
import '../../core/playback/my_list.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tracker/tracker.dart';
import '../../core/tracker/tracker_hub.dart';
import '../../core/playback/watch_history.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/list_status_sheet.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/poster_quick_actions.dart';
import '../../core/ui/states.dart';
import '../../core/ui/tracker_entry_sheet.dart';
import '../auth/auth_cubit.dart';
import '../auth/auth_screens.dart';
import '../detail/detail_screen.dart';
import '../people/favorite_actors_screen.dart';
import '../settings/tracker_settings_screen.dart';
import 'cubit/my_list_cubit.dart';
import 'cubit/tracker_list_cubit.dart';
import 'my_list_screen_tv.dart';
import 'search_screen.dart';

/// My List — one library the user browses by source (their own saved list plus
/// each connected tracker) via a segmented control, and by status via tabs.
/// Trackers are connected/managed from the header's accounts button.
class MyListScreen extends StatelessWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => MyListCubit(sl<MyListStore>(), sl<ListStatusStore>()),
        ),
        BlocProvider(create: (_) => TrackerListCubit()),
      ],
      child: const _MyListView(),
    );
  }
}

class _LibraryTabDef {
  final String key;
  final String label;
  final WatchStatus? status;
  final String? categoryId;
  final String? customList;
  final VoidCallback? onLongPress;

  const _LibraryTabDef({
    required this.key,
    required this.label,
    this.status,
    this.categoryId,
    this.customList,
    this.onLongPress,
  });
}

class _MyListView extends StatefulWidget {
  const _MyListView();

  @override
  State<_MyListView> createState() => _MyListViewState();
}

class _MyListViewState extends State<_MyListView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  late final PageController _pageController;
  final ScrollController _tabScrollController = ScrollController();
  int _activeTabIndex = 0;
  String? _desiredTabKey;

  CategoryStore? get _cats =>
      sl.isRegistered<CategoryStore>() ? sl<CategoryStore>() : null;
  ProviderType? _typeFilter; // null = All

  ListSort? _sort = ListSortPrefs.sortBy;
  bool _sortDesc = ListSortPrefs.descending;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _activeTabIndex);
    _searchCtrl.addListener(() {
      final text = _searchCtrl.text;
      if (text != _searchQuery) {
        setState(() {
          _searchQuery = text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _pageController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  ListSort _sortFor({required bool isMyList}) {
    final chosen = _sort;
    if (chosen != null && optionsFor(isMyList: isMyList).contains(chosen)) {
      return chosen;
    }
    return defaultSortFor(isMyList: isMyList);
  }

  Future<void> _openItem(BuildContext context, MediaItem item, [String? heroTag]) async {
    final cubit = context.read<MyListCubit>();
    await Navigator.push(context, DetailScreen.route(item, heroTag: heroTag));
    cubit.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) return const MyListScreenTv();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<TrackerListCubit, TrackerListState>(
          builder: (context, tlState) {
            final hub = sl<TrackerHub>();
            final connected =
                hub.connectedForMode(sl<ContentModeCubit>().state).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                _searchBar(context),
                if (connected.isNotEmpty)
                  _trackerChips(context, tlState, connected),
                Expanded(
                  child: tlState.isMyList
                      ? _myListBody(context)
                      : _trackerBody(context, tlState),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  int _gridColumns(BuildContext context) {
    if (sl<AppMode>().isDesktop) {
      final width = MediaQuery.sizeOf(context).width;
      if (width >= 1600) return 8;
      if (width >= 1200) return 6;
      if (width >= 900) return 5;
      return 4;
    }
    return 3;
  }

  double _cellW(BuildContext context) {
    final cols = _gridColumns(context);
    return (MediaQuery.sizeOf(context).width - 32 - (12 * (cols - 1))) / cols;
  }

  // ── Header: frosted capsule (no avatar) + search/filter + accounts ─────────

  Widget _header(BuildContext context) {
    final hub = sl<TrackerHub>();
    return AnimatedBuilder(
      // Rebuild when a tracker connects/disconnects.
      animation: Listenable.merge(hub.trackers),
      builder: (context, _) {
        final n = hub
            .connectedForMode(sl<ContentModeCubit>().state)
            .length;
        final subtitle = n == 0
            ? 'Your saved titles'
            : 'My List + $n tracker${n == 1 ? '' : 's'}';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.10),
                  blurRadius: 40,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                        width: 0.5),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Library',
                                style: AppText.title.copyWith(fontSize: 19)),
                            const SizedBox(height: 1),
                            Text(
                              subtitle,
                              style: AppText.caption.copyWith(
                                  color: AppColors.textTertiary, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _pillIcon(
                        Icons.favorite_rounded,
                        'Actors',
                        () => Navigator.of(context).push(FavoriteActorsScreen.route()),
                      ),
                      const SizedBox(width: 8),
                      _pillIcon(
                        _typeFilter == null
                            ? Icons.tune_rounded
                            : Icons.filter_alt_rounded,
                        'Filter',
                        () => _openFilterSheet(context),
                        active: _typeFilter != null,
                      ),
                      const SizedBox(width: 8),
                      _pillIcon(
                        Icons.sort_rounded,
                        'Sort',
                        () => _openSortSheet(context),
                        active: _sort != null,
                      ),
                      const SizedBox(width: 8),
                      _accountsButton(context, hub),
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

  /// Sort options for whichever list is showing. Tapping the active one flips
  /// its direction, which is how the reference apps do it and saves a second
  /// control.
  void _openSortSheet(BuildContext context) {
    final isMyList = context.read<TrackerListCubit>().state.isMyList;
    final options = optionsFor(isMyList: isMyList);
    final active = _sortFor(isMyList: isMyList);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Sort by', style: AppText.title),
            ),
            for (final o in options)
              ListTile(
                title: Text(
                  listSortLabel(o),
                  style: AppText.body.copyWith(
                    color: o == active
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontWeight: o == active ? FontWeight.w700 : null,
                  ),
                ),
                subtitle: o == active
                    ? Text(
                        listSortDirectionLabel(o, _sortDesc),
                        style: AppText.caption,
                      )
                    : null,
                trailing: o == active
                    ? Icon(
                        _sortDesc
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: AppColors.accent,
                        size: 18,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    // Same option again → flip direction; a new one starts in
                    // the direction people expect (best/newest/A-Z first).
                    if (o == active) {
                      _sortDesc = !_sortDesc;
                    } else {
                      _sort = o;
                      _sortDesc = o != ListSort.title;
                    }
                  });
                  ListSortPrefs.save(_sortFor(isMyList: isMyList), _sortDesc);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Create a list on the user's AniList account from the tab row, then
  /// refresh so the new tab appears.
  Future<void> _createAniListList(
    BuildContext context,
    AniListService service,
  ) async {
    final mode = sl<ContentModeCubit>().state;
    final made = await promptCreateAniListList(
      context,
      service,
      mode.isReading ? MediaKind.manga : MediaKind.anime,
    );
    if (made == null || !mounted) return;
    // The names are cached per tracker; creating one is the only thing that
    // changes them, so drop it before re-reading.
    final cubit = this.context.read<TrackerListCubit>();
    cubit.invalidateCustomListNames();
    await cubit.refresh();
  }

  /// Name a new category. Duplicate names are refused by the store (two tabs
  /// reading the same would be indistinguishable), so say so rather than
  /// failing silently.
  Future<void> _createCategory(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('New category', style: AppText.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Persona, Gym, …'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final made = await sl<CategoryStore>().create(name);
    if (!mounted) return;
    if (made == null) {
      showGlobalSnack(
        name.trim().isEmpty ? 'Give it a name' : 'You already have that one',
      );
      return;
    }
    setState(() => _desiredTabKey = 'cat:${made.id}'); // land on the new tab
  }

  /// Rename or delete a category (long-press its tab). Deleting keeps every
  /// title — it only drops the label.
  Future<void> _manageCategory(BuildContext context, ListCategory c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(c.name, style: AppText.title),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: AppColors.accent),
              title: Text('Delete category',
                  style: TextStyle(color: AppColors.accent)),
              subtitle: const Text('Your titles stay — only the label goes'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'delete') {
      await sl<CategoryStore>().delete(c.id);
      if (!mounted) return;
      setState(() {
        _desiredTabKey = 'all';
      });
      return;
    }

    final controller = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: this.context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Rename category', style: AppText.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final ok = await sl<CategoryStore>().rename(c.id, name);
    if (!mounted) return;
    if (!ok) {
      showGlobalSnack('That name is taken');
      return;
    }
    setState(() {});
  }

  Widget _pillIcon(IconData icon, String tooltip, VoidCallback onTap,
      {bool active = false}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? AppColors.accentSoft : AppColors.surface2,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
      ),
    );
  }

  // ── Accounts button (connected avatars + ＋, else "Connect") ───────────────

  Widget _accountsButton(BuildContext context, TrackerHub hub) {
    final connected =
        hub.connectedForMode(sl<ContentModeCubit>().state).toList();
    if (connected.isEmpty) {
      return GestureDetector(
        onTap: () => _openAccountsSheet(context),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Text(
            'Connect',
            style: AppText.caption.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: 13),
          ),
        ),
      );
    }
    final show = connected.take(3).toList();
    return Tooltip(
      message: 'Manage trackers',
      child: GestureDetector(
        onTap: () => _openAccountsSheet(context),
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(7, 0, 11, 0),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24 + (show.length - 1) * 15.0,
                height: 24,
                child: Stack(
                  children: [
                    for (var i = 0; i < show.length; i++)
                      Positioned(left: i * 15.0, child: _miniAvatar(show[i])),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.add_rounded, size: 18, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniAvatar(Tracker t) {
    final url = t.viewerAvatar;
    final letter = t.displayName.isNotEmpty ? t.displayName[0] : '?';
    final Widget inner = (url != null && url.isNotEmpty)
        ? CachedNetworkImage(
            imageUrl: url,
            width: 20,
            height: 20,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => _miniLetter(letter),
          )
        : _miniLetter(letter);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface2, width: 2),
      ),
      child: ClipOval(child: inner),
    );
  }

  Widget _miniLetter(String letter) => Container(
    width: 20,
    height: 20,
    color: AppColors.accent,
    alignment: Alignment.center,
    child: Text(letter,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
  );

  Future<void> _openAccountsSheet(BuildContext context) async {
    final hub = sl<TrackerHub>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Trackers', style: AppText.headline),
              ),
            ),
            for (final t in hub.forMode(sl<ContentModeCubit>().state))
              ListTile(
                leading: SizedBox(
                  width: 34,
                  height: 34,
                  child: (t.isConnected &&
                          (t.viewerAvatar?.isNotEmpty ?? false))
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: t.viewerAvatar!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Icon(
                                Icons.person_rounded,
                                color: AppColors.textTertiary),
                          ),
                        )
                      : Icon(
                          t.isConnected
                              ? Icons.check_circle_rounded
                              : Icons.add_link_rounded,
                          color: t.isConnected
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                ),
                title: Text(t.displayName,
                    style: AppText.body.copyWith(color: AppColors.textPrimary)),
                subtitle: Text(
                  t.isConnected
                      ? 'Connected${t.viewerName != null ? ' · ${t.viewerName}' : ''}'
                      : 'Not connected',
                  style: AppText.caption.copyWith(
                    color: t.isConnected
                        ? AppColors.accent
                        : AppColors.textTertiary,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TrackerSettingsScreen(tracker: t),
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Library search bar & optional tracker chips ────────────────────────────

  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 20,
              color: _searchQuery.isNotEmpty
                  ? AppColors.accent
                  : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: AppText.body.copyWith(fontSize: 14),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: 'Search library...',
                  hintStyle: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trackerChips(
    BuildContext context,
    TrackerListState tlState,
    List<Tracker> connected,
  ) {
    final cubit = context.read<TrackerListCubit>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _sourceChip(
              label: 'My List',
              icon: Icons.bookmark_rounded,
              active: tlState.isMyList,
              onTap: cubit.selectMyList,
            ),
            for (final t in connected) ...[
              const SizedBox(width: 8),
              _sourceChip(
                label: t.displayName == 'MyAnimeList' ? 'MAL' : t.displayName,
                avatarUrl: t.viewerAvatar,
                active: tlState.tracker == t,
                onTap: () => cubit.selectTracker(t),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sourceChip({
    required String label,
    IconData? icon,
    String? avatarUrl,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segAvatar(
              icon: icon,
              avatarUrl: avatarUrl,
              label: label,
              active: active,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.caption.copyWith(
                color: active ? Colors.white : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segAvatar({
    IconData? icon,
    String? avatarUrl,
    required String label,
    required bool active,
  }) {
    final bg = active
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.10);
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: 22,
          height: 22,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(
              label.isNotEmpty ? label[0] : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11),
            ),
          ),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: icon != null
          ? Icon(icon, size: 14, color: Colors.white)
          : Text(
              label.isNotEmpty ? label[0] : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11),
            ),
    );
  }

  // ── Filter sheet (type) ────────────────────────────────────────────────────

  Future<void> _openFilterSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Widget opt(String label, ProviderType? type, IconData icon) {
              final on = _typeFilter == type;
              return ListTile(
                leading: Icon(icon,
                    color: on ? AppColors.accent : AppColors.textSecondary),
                title: Text(
                  label,
                  style: AppText.body.copyWith(
                    color: on ? AppColors.accent : AppColors.textPrimary,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: on
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () {
                  setState(() => _typeFilter = type);
                  setSheet(() {});
                },
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Show', style: AppText.headline),
                  ),
                ),
                opt('All types', null, Icons.apps_rounded),
                opt('Anime', ProviderType.anime, Icons.animation_rounded),
                opt('Movies & TV', ProviderType.movie, Icons.movie_rounded),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── My List body ───────────────────────────────────────────────────────────

  Widget _myListBody(BuildContext context) {
    return BlocBuilder<MyListCubit, List<MyListEntry>>(
      builder: (context, entries) {
        if (entries.isEmpty) return _empty(context);
        return _grid(
          context,
          entries,
          onTap: (item, [heroTag]) => _openItem(context, item, heroTag),
          onMore: (entry) =>
              showListStatusSheet(context, item: entry.item),
        );
      },
    );
  }

  // ── Tracker body (refresh + load/empty/error) ─────────────────────────────

  Widget _trackerBody(BuildContext context, TrackerListState tlState) {
    final Widget content;
    switch (tlState.status) {
      case TrackerListStatus.loading:
        content = Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        );
      case TrackerListStatus.error:
        content = EmptyState(
          icon: Icons.cloud_off_rounded,
          message: 'Couldn’t load this list.',
          actionLabel: 'Retry',
          onAction: () => context.read<TrackerListCubit>().refresh(),
        );
      case TrackerListStatus.idle:
      case TrackerListStatus.ready:
        content = tlState.entries.isEmpty
            ? const EmptyState(
                icon: Icons.bookmark_outline,
                message: 'No titles in this list',
              )
            : _grid(
                context,
                tlState.entries,
                onTap: (item, [heroTag]) =>
                    _openTrackerItem(context, item, heroTag),
                onMore: (entry) => showTrackerEntrySheet(
                  context,
                  tracker: tlState.tracker!,
                  item: entry.item,
                  status: entry.status,
                  progress: entry.progress,
                  score: entry.score,
                  tmdbIsTv: entry.tmdbIsTv,
                  customLists: entry.customLists,
                  onFind: () => _openTrackerItem(context, entry.item),
                  onChanged: () =>
                      context.read<TrackerListCubit>().refresh(),
                ),
              );
    }

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () => context.read<TrackerListCubit>().refresh(),
      child: tlState.status == TrackerListStatus.ready &&
              tlState.entries.isNotEmpty
          ? content
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: content,
                ),
              ],
            ),
    );
  }

  // ── Shared grid: status tabs (with counts) + horizontal swipe PageView ──────

  List<_LibraryTabDef> _buildTabs({
    required List<MyListEntry> modeEntries,
    required bool isMyList,
    required List<String> customLists,
  }) {
    final tabs = <_LibraryTabDef>[];
    tabs.add(const _LibraryTabDef(key: 'all', label: 'All'));

    final isReading = sl<ContentModeCubit>().state.isReading;
    const coreStatuses = [
      WatchStatus.watching,
      WatchStatus.planning,
      WatchStatus.completed,
    ];
    for (final s in coreStatuses) {
      tabs.add(_LibraryTabDef(
        key: 'status:${s.name}',
        label: shortLabelFor(s, reading: isReading),
        status: s,
      ));
    }
    for (final s in [WatchStatus.paused, WatchStatus.dropped]) {
      if (modeEntries.any((e) => e.status == s)) {
        tabs.add(_LibraryTabDef(
          key: 'status:${s.name}',
          label: shortLabelFor(s, reading: isReading),
          status: s,
        ));
      }
    }

    if (isMyList && _cats != null) {
      for (final c in _cats!.all()) {
        tabs.add(_LibraryTabDef(
          key: 'cat:${c.id}',
          label: c.name,
          categoryId: c.id,
          onLongPress: () => _manageCategory(context, c),
        ));
      }
    }

    for (final name in customLists) {
      tabs.add(_LibraryTabDef(
        key: 'custom:$name',
        label: name,
        customList: name,
      ));
    }

    return tabs;
  }

  int _countForTab(_LibraryTabDef tab, List<MyListEntry> modeEntries) {
    return modeEntries.where((e) {
      if (tab.status != null && e.status != tab.status) return false;
      if (tab.categoryId != null) {
        final cats = _cats;
        if (cats == null || !cats.isIn(e.item, tab.categoryId!)) return false;
      }
      if (tab.customList != null && !e.customLists.contains(tab.customList)) {
        return false;
      }
      if (_typeFilter != null && e.item.type != _typeFilter) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        if (!e.item.title.toLowerCase().contains(q)) return false;
      }
      return true;
    }).length;
  }

  void _selectTab(int i) {
    if (i < 0) return;
    setState(() => _activeTabIndex = i);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    _scrollToTab(i);
  }

  void _scrollToTab(int i) {
    if (!_tabScrollController.hasClients) return;
    final target = (i * 90.0) - 30.0;
    final clamped =
        target.clamp(0.0, _tabScrollController.position.maxScrollExtent);
    _tabScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _grid(
    BuildContext context,
    List<MyListEntry> entries, {
    required void Function(MediaItem item, [String? heroTag]) onTap,
    void Function(MyListEntry)? onMore,
  }) {
    final cellW = _cellW(context);
    final mode = sl<ContentModeCubit>().state;
    final modeEntries =
        entries.where((e) => mode.matchesProvider(e.item.type)).toList();

    final trackerState = context.read<TrackerListCubit>().state;
    final isMyList = trackerState.isMyList;

    final customLists = <String>[...trackerState.customListNames];
    for (final e in modeEntries) {
      for (final name in e.customLists) {
        if (!customLists.contains(name)) customLists.add(name);
      }
    }
    customLists.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final tabs = _buildTabs(
      modeEntries: modeEntries,
      isMyList: isMyList,
      customLists: customLists,
    );

    if (_desiredTabKey != null) {
      final idx = tabs.indexWhere((t) => t.key == _desiredTabKey);
      if (idx != -1) {
        _activeTabIndex = idx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(idx);
          }
          _scrollToTab(idx);
        });
      }
      _desiredTabKey = null;
    }

    if (_activeTabIndex >= tabs.length) {
      _activeTabIndex = (tabs.length - 1).clamp(0, 999);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusTabs(
          tabs,
          modeEntries,
          isMyList: isMyList,
          anilist: trackerState.tracker is AniListService
              ? trackerState.tracker as AniListService
              : null,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: tabs.length,
            onPageChanged: (i) {
              setState(() => _activeTabIndex = i);
              _scrollToTab(i);
            },
            itemBuilder: (context, pageIdx) {
              final tabDef = tabs[pageIdx];
              final tabEntries = modeEntries.where((e) {
                if (tabDef.status != null && e.status != tabDef.status) {
                  return false;
                }
                if (tabDef.categoryId != null) {
                  final cats = _cats;
                  if (cats == null || !cats.isIn(e.item, tabDef.categoryId!)) {
                    return false;
                  }
                }
                if (tabDef.customList != null &&
                    !e.customLists.contains(tabDef.customList)) {
                  return false;
                }
                if (_typeFilter != null && e.item.type != _typeFilter) {
                  return false;
                }
                if (_searchQuery.trim().isNotEmpty) {
                  final q = _searchQuery.trim().toLowerCase();
                  if (!e.item.title.toLowerCase().contains(q)) return false;
                }
                return true;
              }).toList();

              final shown = sortLibrary(
                tabEntries,
                _sortFor(isMyList: isMyList),
                _sortDesc,
              );

              if (shown.isEmpty) {
                return _searchQuery.trim().isNotEmpty
                    ? Center(
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          message: 'No titles matching "$_searchQuery"',
                        ),
                      )
                    : EmptyState(
                        icon: Icons.filter_list_off_rounded,
                        message: myListFilteredEmptyMessage(mode),
                      );
              }

              return GridView.builder(
                key: ValueKey('${tabDef.key}|${_sort?.name}|$_sortDesc'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 64),
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: 800,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _gridColumns(context),
                  childAspectRatio: sl<PlaybackPrefs>().hideTitles ? (2 / 3) : 0.62,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final entry = shown[i];
                  final heroTag =
                      'my-list-poster:${entry.item.sourceId}:${entry.item.id}:${tabDef.key}';
                  return RevealItem(
                    index: i,
                    child: PosterCard(
                      title: entry.item.title,
                      imageUrl: entry.item.cover,
                      headers: entry.item.coverHeaders,
                      cellWidth: cellW,
                      heroTag: heroTag,
                      completed: true,
                      onTap: () => onTap(entry.item, heroTag),
                      onLongPress: isMyList
                          ? () => _showMyListQuickActions(context, entry, heroTag)
                          : (onMore == null ? null : () => onMore(entry)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showMyListQuickActions(
    BuildContext context,
    MyListEntry entry,
    String heroTag,
  ) async {
    final item = entry.item;
    final myList = sl<MyListStore>();
    final listStatus = sl<ListStatusStore>();
    final history = sl<WatchHistory>()
        .all()
        .where((e) =>
            e.sourceId == item.sourceId &&
            (e.showId == item.url || e.showUrl == item.url))
        .where((e) => !e.finished)
        .fold<HistoryEntry?>(
          null,
          (best, e) =>
              best == null || e.updatedAt > best.updatedAt ? e : best,
        );
    final watched = entry.status == WatchStatus.completed;
    final inLibrary =
        myList.contains(item) || listStatus.statusOf(item) != null;
    final playLabel = history == null
        ? null
        : 'Resume ${((history.progress * 100).round()).clamp(1, 99)}%';

    await showPosterQuickActions(
      context,
      item: item,
      heroTag: heroTag,
      playLabel: playLabel,
      inLibrary: inLibrary,
      watched: watched,
      onPlay: () => _openItem(context, item),
      onInfo: () => _openItem(context, item),
      onStatus: () async {
        await showListStatusSheet(context, item: item);
        if (context.mounted) context.read<MyListCubit>().reload();
      },
      onMarkWatched: () async {
        if (!myList.contains(item)) await myList.add(item);
        await listStatus.setStatus(item, WatchStatus.completed);
        await myList.pushStatus(item);
        if (context.mounted) context.read<MyListCubit>().reload();
      },
      onToggleLibrary: () async {
        await myList.toggle(item);
        if (!myList.contains(item)) {
          await listStatus.remove(item);
        }
        if (context.mounted) context.read<MyListCubit>().reload();
        return myList.contains(item);
      },
    );
  }

  /// Open a tracker entry. Simkl movie/TV entries already carry a TMDB id, so
  /// opening the catalog directly is both faster and deterministic. Anime/MAL
  /// entries still use title search because the tracker deliberately stores no
  /// streaming-provider URL.
  Future<void> _openTrackerItem(BuildContext context, MediaItem stub, [String? heroTag]) async {
    if (stub.tmdbId != null) {
      final item = MediaItem(
        id: 'tmdb:${stub.tmdbIsTv ? 'tv' : 'movie'}:${stub.tmdbId}',
        title: stub.title,
        cover: stub.cover,
        url: 'tmdb://${stub.tmdbIsTv ? 'tv' : 'movie'}/${stub.tmdbId}',
        type: ProviderType.movie,
        sourceId: 'tmdb:catalog',
        tmdbId: stub.tmdbId,
        tmdbIsTv: stub.tmdbIsTv,
      );
      await Navigator.of(context).push(DetailScreen.route(item, heroTag: heroTag));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchScreen(initialQuery: stub.title),
      ),
    );
  }

  // ── Status tabs (counts baked into the labels) ─────────────────────────────

  Widget _statusTabs(
    List<_LibraryTabDef> tabs,
    List<MyListEntry> modeEntries, {
    required bool isMyList,
    AniListService? anilist,
  }) {
    Widget tab(
      String label,
      bool active,
      int count,
      VoidCallback onTap, {
      VoidCallback? onLongPress,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(right: 22),
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.accent : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppText.body.copyWith(
                  color: active ? AppColors.accent : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: AppText.caption.copyWith(
                  color: active ? AppColors.accent : AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: SizedBox(
        height: 42,
        child: ListView(
          controller: _tabScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 16),
          children: [
            for (int i = 0; i < tabs.length; i++)
              tab(
                tabs[i].label,
                _activeTabIndex == i,
                _countForTab(tabs[i], modeEntries),
                () => _selectTab(i),
                onLongPress: tabs[i].onLongPress,
              ),
            if (!isMyList && anilist != null)
              GestureDetector(
                onTap: () => _createAniListList(context, anilist),
                child: Container(
                  margin: const EdgeInsets.only(right: 22),
                  padding: const EdgeInsets.only(top: 8, bottom: 10),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            if (isMyList && _cats != null)
              GestureDetector(
                onTap: () => _createCategory(context),
                child: Container(
                  margin: const EdgeInsets.only(right: 22),
                  padding: const EdgeInsets.only(top: 8, bottom: 10),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Empty / sign-in ────────────────────────────────────────────────────────

  Widget _empty(BuildContext context) {
    final auth = context.watch<AuthCubit>().state;
    if (!auth.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bookmark_outline,
                  size: 56, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text(
                'Sign in to build your list',
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 180,
                child: PrimaryButton(
                  label: 'Sign in',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return EmptyState(
      icon: Icons.bookmark_outline,
      message: myListEmptyMessage(sl<ContentModeCubit>().state),
    );
  }
}

/// EmptyState message for My List's per-status/type filter turning up
/// nothing (the mode filter itself is applied before this — see [_grid]).
/// Anime mode's wording is unchanged; a reading mode names its own content
/// type instead of the generic "Nothing".
String myListFilteredEmptyMessage(ContentMode mode) => switch (mode) {
  ContentMode.anime => 'Nothing here in this filter',
  ContentMode.manga => 'No manga here in this filter',
  ContentMode.novel => 'No novels here in this filter',
};

/// EmptyState message for a genuinely empty My List (nothing saved yet, of
/// ANY type). Anime mode's wording is unchanged.
String myListEmptyMessage(ContentMode mode) => switch (mode) {
  ContentMode.anime => 'Titles you add appear here',
  ContentMode.manga => 'Manga you add appear here',
  ContentMode.novel => 'Novels you add appear here',
};
