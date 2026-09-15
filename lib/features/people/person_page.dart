import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/metadata/people_service.dart';
import '../../core/metadata/theporndb.dart';
import '../../core/models/media_item.dart';
import '../../core/models/person.dart';
import '../../core/models/provider_info.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/states.dart';
import '../detail/detail_screen.dart';

/// A person page — an anime character or voice actor/staff (AniList), or a
/// movie/TV person (TMDB). Opened from the Detail screen's Cast tab. Metadata
/// only: it never touches a provider except to open a tapped title in the
/// active source (searched by title, like the Relations tab).
class PersonPage extends StatefulWidget {
  const PersonPage({super.key, required this.person, this.sourceId});

  final PersonRef person;

  /// The source to search when a title on this page is tapped. Null → active.
  final String? sourceId;

  static Route<void> route(PersonRef person, {String? sourceId}) =>
      MaterialPageRoute<void>(
        builder: (_) => PersonPage(person: person, sourceId: sourceId),
      );

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  final ScrollController _scrollController = ScrollController();
  PersonProfile? _profile;
  bool _loading = true;
  final List<PersonWork> _works = [];
  int _page = 1;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _bioExpanded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadProfile();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await sl<PeopleService>().load(widget.person);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _loading = false;
      if (p != null) {
        _works.addAll(p.works);
        _hasMore = p.works.length >= 30 && widget.person.source == PersonSource.thePornDbPerformer;
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final more = await sl<PeopleService>().loadWorks(widget.person, page: nextPage);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (more.isEmpty) {
        _hasMore = false;
      } else {
        _page = nextPage;
        final existingIds = {for (final w in _works) w.catalogId ?? w.title};
        for (final w in more) {
          if (existingIds.add(w.catalogId ?? w.title)) {
            _works.add(w);
          }
        }
        if (more.length < 30) {
          _hasMore = false;
        }
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Open a title from this person's works — search the active source by title
  /// and open the first match (same approach as the Relations tab).
  Future<void> _openWork(PersonWork w) async {
    _snack('Finding “${w.title}”…');
    try {
      if (widget.person.source == PersonSource.thePornDbPerformer) {
        // Performer works are TPDB-owned. Prefer the source-native movie id so
        // a similarly named movie can never replace the one in the performer
        // profile. Title search is only the fallback for older API rows without
        // an id.
        MediaItem? match;
        if (w.catalogId != null && w.catalogId!.isNotEmpty) {
          match = MediaItem(
            id: 'tpdb:movie:${w.catalogId}',
            title: w.title,
            cover: w.cover,
            url: 'tpdb://movie/${w.catalogId}',
            type: ProviderType.movie,
            sourceId: 'tpdb:catalog',
          );
        } else {
          final results = await sl<ThePornDb>().search(w.title);
          if (!mounted) return;
          final wanted = normalizeTitle(w.title);
          for (final candidate in results) {
            if (normalizeTitle(candidate.title) == wanted) {
              match = candidate;
              break;
            }
          }
        }
        if (match == null) { _snack('“${w.title}” isn’t in ThePornDB'); return; }
        Navigator.of(context).push(DetailScreen.route(match));
        return;
      }
      final results = await sl<SourceRepository>().search(w.title, sourceId: widget.sourceId);
      if (!mounted) return;
      final match = bestTitleMatch(
        results,
        w.title,
        altTitle: w.romaji,
        wantedMalId: w.malId,
      );
      if (match == null) {
        _snack('“${w.title}” isn’t on this source');
        return;
      }
      Navigator.of(context).push(DetailScreen.route(match));
    } catch (_) {
      if (mounted) _snack('Couldn’t open “${w.title}”');
    }
  }

  void _openRelated(PersonRef ref) {
    Navigator.of(context).push(PersonPage.route(ref, sourceId: widget.sourceId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(
          widget.person.name,
          style: AppText.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _profile == null
              ? const EmptyState(
                  icon: Icons.person_off_outlined,
                  message: 'Couldn’t load this profile',
                )
              : _content(_profile!),
    );
  }

  Widget _content(PersonProfile p) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _header(p)),
        if (p.description != null && p.description!.isNotEmpty)
          SliverToBoxAdapter(child: _bio(p.description!)),
        if (p.related.isNotEmpty)
          SliverToBoxAdapter(child: _relatedRow(p.related)),
        if (_works.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _sectionLabel(
              widget.person.source == PersonSource.anilistStaff
                  ? 'Roles'
                  : 'Appears in',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _workCard(_works[i]),
                childCount: _works.length,
              ),
            ),
          ),
          if (_loadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _header(PersonProfile p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 118,
              height: 158,
              child: (p.photo != null && p.photo!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: p.photo!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: AppColors.surface2),
                      errorWidget: (_, _, _) => const _PortraitFallback(),
                    )
                  : const _PortraitFallback(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(p.name, style: AppText.title),
                if (p.nativeName != null && p.nativeName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p.nativeName!, style: AppText.body),
                ],
                if (p.subtitle != null && p.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      p.subtitle!,
                      style: AppText.caption.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bio(String text) {
    return GestureDetector(
      onTap: () => setState(() => _bioExpanded = !_bioExpanded),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              maxLines: _bioExpanded ? null : 4,
              overflow: _bioExpanded ? null : TextOverflow.ellipsis,
              style: AppText.body,
            ),
            const SizedBox(height: 4),
            Text(
              _bioExpanded ? 'Show less' : 'Read more',
              style: AppText.caption.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _relatedRow(List<PersonRef> people) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Voiced by'),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            itemCount: people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final r = people[i];
              return GestureDetector(
                onTap: () => _openRelated(r),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: (r.photo != null && r.photo!.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: r.photo!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      Container(color: AppColors.surface2),
                                  errorWidget: (_, _, _) =>
                                      const _PortraitFallback(),
                                )
                              : const _PortraitFallback(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(text, style: AppText.overline),
      );

  Widget _workCard(PersonWork w) {
    return GestureDetector(
      onTap: () => _openWork(w),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: (w.cover != null && w.cover!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: w.cover!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: AppColors.surface2),
                      errorWidget: (_, _, _) =>
                          Container(color: AppColors.surface2),
                    )
                  : Container(color: AppColors.surface2),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            w.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.textPrimary),
          ),
          if (w.subtitle != null && w.subtitle!.isNotEmpty)
            Text(
              w.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _PortraitFallback extends StatelessWidget {
  const _PortraitFallback();
  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surface2,
        alignment: Alignment.center,
        child: const Icon(
          Icons.person_rounded,
          color: AppColors.textTertiary,
          size: 34,
        ),
      );
}
