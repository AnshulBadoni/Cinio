import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../playback/external_player.dart';
import '../playback/source_selection.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'native_cover_provider.dart';

/// What a long-press on an episode chose: which player to open it in, this
/// once. An empty [package] means the built-in player.
typedef PlayerChoice = ({String package, String label});

/// What the long-press menu was asked to do. The player pick is its own sheet,
/// so this only carries the actions that don't need further input.
enum EpisodeAction {
  /// Open the "play this episode with" sheet.
  pickPlayer,

  /// Drop this episode's cached links and play again. For when a mirror has
  /// expired and every attempt fails on links that looked fine 20 minutes ago.
  reloadLinks,

  /// Flip this episode's watched state by hand, and move any connected
  /// tracker with it.
  toggleWatched,

  /// Mark this episode and everything before it watched — the "came back
  /// mid-season" case, where marking twelve episodes one at a time is the
  /// reason people give up and edit their list on the website instead.
  markAboveWatched,

  /// Resolve the episode's mirrors and pick one before anything plays, rather
  /// than starting on whichever the app chose and switching afterwards.
  playMirror,
}

/// The centered long-press action surface for an episode. The selected
/// thumbnail is brought into focus while the detail page behind it is blurred
/// and dimmed. Keeping the action surface independent from playback resolution
/// lets the caller reuse the same state and player logic.
Future<EpisodeAction?> showEpisodeActionSheet(
  BuildContext context, {
  required String episodeLabel,
  required String currentPlayerLabel,
  required bool isWatched,
  required bool tracksToServices,
  String? thumbnailUrl,
  Map<String, String>? thumbnailHeaders,
  String? fallbackThumbnailUrl,
  Map<String, String>? fallbackThumbnailHeaders,
  double? rating,
  String? heroTag,
  String? episodeTag,
  String? description,
  int? runtimeMinutes,
  String? formattedDate,
  bool isFiller = false,
  bool isResume = false,
  double fraction = 0.0,
  bool isInProgress = false,
}) async {
  if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
    unawaited(precacheImage(
      nativeCoverProvider(thumbnailUrl, thumbnailHeaders),
      context,
    ).catchError((_) {}));
  }
  if (fallbackThumbnailUrl != null && fallbackThumbnailUrl.isNotEmpty) {
    unawaited(precacheImage(
      nativeCoverProvider(fallbackThumbnailUrl, fallbackThumbnailHeaders),
      context,
    ).catchError((_) {}));
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<EpisodeAction>(
    PageRouteBuilder<EpisodeAction>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          _EpisodeQuickActions(
        episodeLabel: episodeLabel,
        currentPlayerLabel: currentPlayerLabel,
        isWatched: isWatched,
        tracksToServices: tracksToServices,
        thumbnailUrl: thumbnailUrl,
        thumbnailHeaders: thumbnailHeaders,
        fallbackThumbnailUrl: fallbackThumbnailUrl,
        fallbackThumbnailHeaders: fallbackThumbnailHeaders,
        rating: rating,
        heroTag: heroTag,
        episodeTag: episodeTag,
        description: description,
        runtimeMinutes: runtimeMinutes,
        formattedDate: formattedDate,
        isFiller: isFiller,
        isResume: isResume,
        fraction: fraction,
        isInProgress: isInProgress,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.fastOutSlowIn,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    ),
  );
}

class _EpisodeQuickActions extends StatelessWidget {
  const _EpisodeQuickActions({
    required this.episodeLabel,
    required this.currentPlayerLabel,
    required this.isWatched,
    required this.tracksToServices,
    this.thumbnailUrl,
    this.thumbnailHeaders,
    this.fallbackThumbnailUrl,
    this.fallbackThumbnailHeaders,
    this.rating,
    this.heroTag,
    this.episodeTag,
    this.description,
    this.runtimeMinutes,
    this.formattedDate,
    this.isFiller = false,
    this.isResume = false,
    this.fraction = 0.0,
    this.isInProgress = false,
  });

  final String episodeLabel;
  final String currentPlayerLabel;
  final bool isWatched;
  final bool tracksToServices;
  final String? thumbnailUrl;
  final Map<String, String>? thumbnailHeaders;
  final String? fallbackThumbnailUrl;
  final Map<String, String>? fallbackThumbnailHeaders;
  final double? rating;
  final String? heroTag;
  final String? episodeTag;
  final String? description;
  final int? runtimeMinutes;
  final String? formattedDate;
  final bool isFiller;
  final bool isResume;
  final double fraction;
  final bool isInProgress;

  Widget _centeredEpisodeCard(BuildContext context) {
    final effectiveUrl = (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
        ? thumbnailUrl!
        : (fallbackThumbnailUrl ?? '');
    final effectiveHeaders = (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
        ? thumbnailHeaders
        : fallbackThumbnailHeaders;

    Widget card = Container(
      width: 295,
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Thumbnail Image
          effectiveUrl.isNotEmpty
              ? Image(
                  image: nativeCoverProvider(effectiveUrl, effectiveHeaders),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: AppColors.surface2,
                    child: const Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: AppColors.textTertiary,
                        size: 36,
                      ),
                    ),
                  ),
                )
              : ColoredBox(
                  color: AppColors.surface2,
                  child: const Center(
                    child: Icon(
                      Icons.movie_outlined,
                      color: AppColors.textTertiary,
                      size: 36,
                    ),
                  ),
                ),

          // 2. Dark Gradient Overlay (Exact match to _WideEpisodeCard)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0.98),
                ],
                stops: const [0.0, 0.28, 0.65, 1.0],
              ),
            ),
          ),

          // 3. Top-left Season/Episode Badge
          if (episodeTag != null && episodeTag!.isNotEmpty)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  episodeTag!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),

          // 4. Top-right Badges (Watched checkmark, Filler tag)
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFiller) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'FILLER',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (isWatched)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
              ],
            ),
          ),

          // 5. Overlaid bottom content (Title, Overview synopsis, runtime, rating, date)
          Positioned(
            left: 12,
            right: 12,
            bottom: (isInProgress || fraction > 0) ? 8 : 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  episodeLabel,
                  style: TextStyle(
                    color: isResume ? AppColors.accent : Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!.trim(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (runtimeMinutes != null) ...[
                      Text(
                        '${runtimeMinutes}m',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (rating != null && rating! > 0) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5C518),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'IMDb',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    if (formattedDate != null && formattedDate!.isNotEmpty)
                      Text(
                        formattedDate!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 6. Resume progress bar at bottom edge
          if (isInProgress || fraction > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
            ),
        ],
      ),
    );

    if (heroTag != null && heroTag!.isNotEmpty) {
      card = Hero(
        tag: heroTag!,
        createRectTween: (begin, end) => RectTween(begin: begin, end: end),
        flightShuttleBuilder: (context, animation, direction, fromHero, toHero) =>
            direction == HeroFlightDirection.push ? fromHero.widget : toHero.widget,
        child: card,
      );
    }
    return card;
  }

  void _close(BuildContext context, EpisodeAction action) {
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.68),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: size.height - 40,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _centeredEpisodeCard(context),
                      const SizedBox(height: 20),
                      _EpisodeActionButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play with',
                        trailing: currentPlayerLabel,
                        primary: true,
                        onTap: () => _close(context, EpisodeAction.pickPlayer),
                      ),
                      const SizedBox(height: 8),
                      _EpisodeActionButton(
                        icon: Icons.swap_horiz_rounded,
                        label: 'Play mirror',
                        onTap: () => _close(context, EpisodeAction.playMirror),
                      ),
                      const SizedBox(height: 8),
                      _EpisodeActionButton(
                        icon: Icons.refresh_rounded,
                        label: 'Reload links',
                        onTap: () => _close(context, EpisodeAction.reloadLinks),
                      ),
                      const SizedBox(height: 8),
                      _EpisodeActionButton(
                        icon: isWatched
                            ? Icons.remove_done_rounded
                            : Icons.check_rounded,
                        label: isWatched ? 'Mark as unwatched' : 'Mark as watched',
                        subtitle: tracksToServices
                            ? 'Also updates your connected trackers'
                            : null,
                        onTap: () => _close(context, EpisodeAction.toggleWatched),
                      ),
                      const SizedBox(height: 8),
                      _EpisodeActionButton(
                        icon: Icons.done_all_rounded,
                        label: 'Mark this and all above as watched',
                        onTap: () => _close(
                          context,
                          EpisodeAction.markAboveWatched,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeActionButton extends StatelessWidget {
  const _EpisodeActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final String? trailing;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : AppColors.textPrimary;
    final background = primary ? AppColors.accent : AppColors.surface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.button.copyWith(color: foreground, fontSize: 15),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: primary
                              ? Colors.white.withValues(alpha: 0.78)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: primary
                          ? Colors.white.withValues(alpha: 0.82)
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick where an episode plays, for this episode only.
///
/// Deliberately doesn't touch [PlaybackPrefs.externalPlayerPackage]: Settings
/// stays the place that says "always use X", and trying VLC once shouldn't
/// quietly rewire every future tap.
///
/// Returns null when dismissed — a long-press that starts playback on its own
/// would be a trap.
Future<PlayerChoice?> showEpisodePlayerSheet(
  BuildContext context, {
  required String episodeLabel,
  required String defaultPackage,
}) async {
  final installed = await ExternalPlayer().installed();
  if (!context.mounted) return null;

  return showModalBottomSheet<PlayerChoice>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // The list is short, but a device with several players installed plus a
    // long episode title shouldn't push the last row off-screen.
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: SingleChildScrollView(
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Play this episode with', style: AppText.headline),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    episodeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              _PlayerRow(
                icon: Icons.play_circle_outline_rounded,
                label: 'Built-in player',
                isDefault: defaultPackage.isEmpty,
                onTap: () => Navigator.pop(
                  sheetContext,
                  (package: '', label: 'Built-in player'),
                ),
              ),
              for (final p in installed.where((p) => p.known))
                _PlayerRow(
                  icon: Icons.open_in_new_rounded,
                  label: p.label,
                  isDefault: defaultPackage == p.package,
                  onTap: () => Navigator.pop(
                    sheetContext,
                    (package: p.package, label: p.label),
                  ),
                ),
              // Everything else on the device that answers a video intent. They
              // play — header-gated streams too, via the local proxy — but we
              // don't know which intent extras they read, so external subtitles
              // and the resume position may be ignored. Under their own heading
              // because some are galleries or browsers rather than players at
              // all, hence "apps", not "players".
              if (installed.any((p) => !p.known)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Other apps',
                      style: AppText.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                for (final p in installed.where((p) => !p.known))
                  _PlayerRow(
                    icon: Icons.open_in_new_rounded,
                    label: p.label,
                    isDefault: defaultPackage == p.package,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      (package: p.package, label: p.label),
                    ),
                  ),
              ],
              // Opening an empty sheet on long-press reads as a broken gesture,
              // so say why there's only one row rather than showing nothing.
              if (installed.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                    'No other video apps installed. VLC, MX Player and '
                    'Just Player all show up here once installed.',
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Pick one of an episode's resolved mirrors.
///
/// Takes already-resolved sources rather than resolving itself: the caller
/// shows its own progress while scraping, and a sheet that opens empty and
/// fills in later is worse than one that opens with the answer.
Future<VideoSource?> showMirrorSheet(
  BuildContext context, {
  required String episodeLabel,
  required List<VideoSource> sources,
}) {
  final kinds = availableKinds(sources);
  return showModalBottomSheet<VideoSource>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        child: SingleChildScrollView(
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Play mirror', style: AppText.headline),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    episodeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              for (final k in kinds)
                for (final s in sortByQuality(sourcesForKind(sources, k)))
                  _PlayerRow(
                    icon: Icons.play_arrow_rounded,
                    // Same shape the player's own Sources sheet uses: the
                    // provider's mirror name when it has one, otherwise the
                    // audio kind — and never a stray "UNKNOWN •" for sources
                    // that don't declare sub/dub.
                    label: s.label?.trim().isNotEmpty == true
                        ? s.label!.trim()
                        : '${k != AudioKind.unknown ? '${k.name.toUpperCase()} • ' : ''}'
                              '${s.quality ?? s.container.name.toUpperCase()}',
                    subtitle: s.label?.trim().isNotEmpty == true
                        ? s.quality
                        : null,
                    onTap: () => Navigator.pop(sheetContext, s),
                  ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDefault = false,
    this.subtitle,
    this.trailingText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Marks the row a plain tap would have used. Marked rather than sorted to
  /// the top, so the list doesn't reshuffle when the Settings default changes.
  final bool isDefault;
  final String? subtitle;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final trailing = trailingText ?? (isDefault ? 'Default' : null);
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(label, style: AppText.body),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
      trailing: trailing == null
          ? null
          : Text(
              trailing,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
      onTap: onTap,
    );
  }
}
