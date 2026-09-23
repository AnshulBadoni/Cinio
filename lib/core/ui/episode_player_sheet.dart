import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/video_source.dart';
import '../playback/external_player.dart';
import '../playback/source_selection.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

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
  String? heroTag,
}) {
  return showGeneralDialog<EpisodeAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Episode actions',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (dialogContext, _, _) => _EpisodeQuickActions(
      episodeLabel: episodeLabel,
      currentPlayerLabel: currentPlayerLabel,
      isWatched: isWatched,
      tracksToServices: tracksToServices,
      thumbnailUrl: thumbnailUrl,
      thumbnailHeaders: thumbnailHeaders,
      heroTag: heroTag,
    ),
    transitionBuilder: (dialogContext, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
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
    this.heroTag,
  });

  final String episodeLabel;
  final String currentPlayerLabel;
  final bool isWatched;
  final bool tracksToServices;
  final String? thumbnailUrl;
  final Map<String, String>? thumbnailHeaders;
  final String? heroTag;

  Widget _thumbnail(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.72).clamp(260.0, 460.0);
    final height = width * 9 / 16;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        height: height,
        child: thumbnailUrl == null || thumbnailUrl!.isEmpty
            ? ColoredBox(color: AppColors.surface2)
            : CachedNetworkImage(
                imageUrl: thumbnailUrl!,
                httpHeaders: thumbnailHeaders,
                fit: BoxFit.cover,
                memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (_, _) => const ColoredBox(color: AppColors.surface2),
                errorWidget: (_, _, _) => const ColoredBox(color: AppColors.surface2),
              ),
      ),
    );
    if (heroTag == null) return image;
    return Hero(tag: heroTag!, child: image);
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
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.68)),
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
                      _thumbnail(context),
                      const SizedBox(height: 18),
                      Text(
                        episodeLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title,
                      ),
                      const SizedBox(height: 18),
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
