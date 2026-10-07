import 'package:equatable/equatable.dart';

/// Where a person page's data comes from (and which query to run).
enum PersonSource { anilistCharacter, anilistStaff, tmdb, thePornDbPerformer, thePornDbStudio }

/// A tappable reference to a person page — an anime character or voice
/// actor/staff (AniList), or a movie/TV person (TMDB). Carried on
/// [CastMember] so a cast card can open the person's page, and used for links
/// between pages (a character's voice actors, etc.). Runtime-only.
class PersonRef extends Equatable {
  const PersonRef({
    required this.id,
    required this.source,
    required this.name,
    this.photo,
    this.externalId,
  });

  final int id;
  final PersonSource source;

  /// Shown as the page title while the full profile loads.
  final String name;

  /// Shown as the hero image while the full profile loads.
  final String? photo;

  /// Source-native string id for catalogs whose identifiers are not integers.
  /// TPDB performers commonly use string/UUID-like identifiers.
  final String? externalId;

  @override
  List<Object?> get props => [id, source, name, photo, externalId];

  PersonRef copyWith({
    int? id,
    PersonSource? source,
    String? name,
    String? photo,
    String? externalId,
  }) =>
      PersonRef(
        id: id ?? this.id,
        source: source ?? this.source,
        name: name ?? this.name,
        photo: photo ?? this.photo,
        externalId: externalId ?? this.externalId,
      );
}

/// A fully-loaded person profile shown on the person page.
class PersonProfile extends Equatable {
  const PersonProfile({
    required this.name,
    this.nativeName,
    this.photo,
    this.description,
    this.subtitle,
    this.works = const [],
    this.providerVideos = const [],
    this.related = const [],
  });

  final String name;
  final String? nativeName;
  final String? photo;

  /// Bio / description. May carry light HTML/markdown from AniList — the page
  /// strips tags and renders it as plain text.
  final String? description;

  /// Small line under the name, e.g. "Voice Actor" / "Acting".
  final String? subtitle;

  /// Media this person appears in / worked on.
  final List<PersonWork> works;

  /// Provider videos / scene clips with wider 16:9 images.
  final List<PersonWork> providerVideos;

  /// Linked people (e.g. co-stars / voice actors) shown as circular avatars.
  final List<PersonRef> related;

  @override
  List<Object?> get props =>
      [name, nativeName, photo, description, subtitle, works, providerVideos, related];
}

/// One media entry on a person page (a role / appearance). Tapping opens the
/// title in the active source (searched by [title], like the Relations tab).
class PersonWork extends Equatable {
  const PersonWork({
    required this.title,
    this.romaji,
    this.cover,
    this.subtitle,
    this.malId,
    this.catalogId,
    this.isTv = false,
    this.releaseDate,
    this.rating,
    this.popularity,
    this.backdrop,
    this.isScene = false,
  });

  final String title;

  /// Romaji title (AniList works), so a tap also matches Romaji-indexed sources.
  final String? romaji;

  final String? cover;

  /// e.g. the character voiced, the job, or the role.
  final String? subtitle;

  /// MAL id (AniList works) — the reliable signal for opening the exact title
  /// on the source. Null for TMDB works (matched by title instead).
  final int? malId;

  /// Catalog-native id for source-owned works (e.g. ThePornDB movie id).
  final String? catalogId;

  /// Whether this title is a television series (vs feature film).
  final bool isTv;

  /// Release date (e.g. "2023-11-10" or "2023").
  final String? releaseDate;

  /// Viewer rating score (0.0 to 10.0).
  final double? rating;

  /// Popularity score for ranking.
  final double? popularity;

  /// Wide backdrop/thumbnail image for 16:9 video representation.
  final String? backdrop;

  /// Whether this entry is an individual provider scene/video clip.
  final bool isScene;

  @override
  List<Object?> get props => [
        title,
        romaji,
        cover,
        subtitle,
        malId,
        catalogId,
        isTv,
        releaseDate,
        rating,
        popularity,
        backdrop,
        isScene,
      ];
}
