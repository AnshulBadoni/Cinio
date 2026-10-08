import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/metadata/favorite_people_store.dart';
import '../../core/models/person.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/states.dart';
import 'person_page.dart';

/// Screen displaying all actors and performers favorited (liked) by the user.
class FavoriteActorsScreen extends StatefulWidget {
  const FavoriteActorsScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const FavoriteActorsScreen(),
      );

  @override
  State<FavoriteActorsScreen> createState() => _FavoriteActorsScreenState();
}

class _FavoriteActorsScreenState extends State<FavoriteActorsScreen> {
  final FavoritePeopleStore _store = sl<FavoritePeopleStore>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar('Favorite Actors'),
      body: ValueListenableBuilder(
        valueListenable: _store.listenable() ?? ValueNotifier(null),
        builder: (context, _, __) {
          final favorites = _store.allFavorites();
          if (favorites.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_border_rounded,
              message: 'No favorite actors yet',
              actionLabel: null,
            );
          }

          final width = MediaQuery.sizeOf(context).width;
          final cols = width >= 900 ? 5 : (width >= 600 ? 4 : 3);

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 0.72,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
            ),
            itemCount: favorites.length,
            itemBuilder: (context, i) {
              final person = favorites[i];
              return _ActorCard(
                person: person,
                onTap: () {
                  Navigator.of(context).push(PersonPage.route(person));
                },
                onRemove: () async {
                  await _store.toggleFavorite(person);
                  if (mounted) setState(() {});
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ActorCard extends StatelessWidget {
  const _ActorCard({
    required this.person,
    required this.onTap,
    required this.onRemove,
  });

  final PersonRef person;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final photo = person.photo;
    final isTpdb = person.source == PersonSource.thePornDbPerformer ||
        person.source == PersonSource.thePornDbStudio;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: photo != null && photo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            placeholder: (_, _) =>
                                Container(color: AppColors.surface2),
                            errorWidget: (_, _, _) => Container(
                              color: AppColors.surface2,
                              child: const Icon(
                                Icons.person_rounded,
                                color: AppColors.textTertiary,
                                size: 40,
                              ),
                            ),
                          )
                        : Container(
                            color: AppColors.surface2,
                            child: const Icon(
                              Icons.person_rounded,
                              color: AppColors.textTertiary,
                              size: 40,
                            ),
                          ),
                  ),
                ),
                // Liked heart badge in top-right
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.60),
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFFF2D55),
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Avoin',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isTpdb ? 'Performer' : 'Actor',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
