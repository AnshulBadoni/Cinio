import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/episode_title.dart' show cleanTitle;
import '../models/provider_info.dart';
import 'nsfw_trailer_service.dart';

export 'nsfw_trailer_service.dart'
    show
        AlternateTrailer,
        NsfwTrailerService,
        TrailerAlternateContext,
        TrailerAlternateType;

/// Unified representation of a resolved trailer stream.
///
/// Can represent either a YouTube video ID (resolved to playable streams via
/// [TrailerService.streamUrl]) or a direct stream URL (e.g. HLS .m3u8) with
/// required HTTP headers.
class TrailerInfo {
  final String key;
  final String name;
  final String type;
  final String site;

  const TrailerInfo({
    required this.key,
    required this.name,
    this.type = 'Trailer',
    this.site = 'YouTube',
  });

  String get thumbnailUrl => 'https://img.youtube.com/vi/$key/hqdefault.jpg';
  TrailerSource toSource() => TrailerSource.youtube(key);
}

class TrailerSource {
  const TrailerSource.youtube(this.youtubeId)
      : directUrl = null,
        headers = null;

  const TrailerSource.direct({
    required String url,
    this.headers,
  })  : directUrl = url,
        youtubeId = null;

  final String? youtubeId;
  final String? directUrl;
  final Map<String, String>? headers;

  bool get isDirect => directUrl != null && directUrl!.isNotEmpty;
  bool get isYoutube => youtubeId != null && youtubeId!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrailerSource &&
          runtimeType == other.runtimeType &&
          youtubeId == other.youtubeId &&
          directUrl == other.directUrl;

  @override
  int get hashCode => youtubeId.hashCode ^ directUrl.hashCode;
}

class TrailerService {
  TrailerService(this._dio, [NsfwTrailerService? nsfwTrailerService])
      : _nsfwTrailerService = nsfwTrailerService ?? NsfwTrailerService(_dio);

  final Dio _dio;
  final NsfwTrailerService _nsfwTrailerService;

  static const String _anilistEndpoint = 'https://graphql.anilist.co';
  // TMDB v3 — api_key attached by the Dio interceptor (initDependencies).
  static const String _tmdbBase = 'https://api.themoviedb.org/3';

  static const String _anilistQuery =
      'query(\$search:String){ Media(search:\$search, type:ANIME){ '
      'id title{romaji english} trailer{ id site } } }';

  /// Resolves a playable [TrailerSource] for a title.
  ///
  /// Resolution priority:
  /// 1. If [alternateContext] is non-null (NSFW trailers toggle ON + model/studio context),
  ///    attempt adult trailer lookup via [NsfwTrailerService].
  /// 2. If an alternate trailer is found, returns [TrailerSource.direct].
  /// 3. Otherwise (or on failure), fall back to normal metadata lookup (AniList / TMDB)
  ///    returning [TrailerSource.youtube].
  Future<TrailerSource?> resolveTrailer({
    required String title,
    String? englishTitle,
    required ProviderType type,
    String? year,
    TrailerAlternateContext? alternateContext,
    String? tpdbId,
    int? tmdbId,
    bool? isTv,
  }) async {
    if (alternateContext != null) {
      try {
        final alternate = await _nsfwTrailerService.fetch(
          context: alternateContext,
          tpdbId: tpdbId,
        );
        if (alternate != null && alternate.url.isNotEmpty) {
          return TrailerSource.direct(
            url: alternate.url,
            headers: alternate.headers,
          );
        }
      } catch (_) {
        // Silently fall back to normal trailer
      }
    }

    final ytId = await youtubeId(
      title: title,
      englishTitle: englishTitle,
      type: type,
      year: year,
      tmdbId: tmdbId,
      isTv: isTv,
    );
    if (ytId != null && ytId.isNotEmpty) {
      return TrailerSource.youtube(ytId);
    }
    return null;
  }

  /// Returns a YouTube video id for the title, or null. Cheap + best-effort.
  Future<String?> youtubeId({
    required String title,
    String? englishTitle,
    required ProviderType type,
    String? year,
    TrailerAlternateContext? alternateContext,
    int? tmdbId,
    bool? isTv,
  }) async {
    switch (type) {
      case ProviderType.anime:
        return _anilistTrailer(title: title, englishTitle: englishTitle);
      case ProviderType.movie:
        return _tmdbTrailer(
          title: title,
          englishTitle: englishTitle,
          year: year,
          tmdbId: tmdbId,
          isTv: isTv,
        );
      case ProviderType.manga:
      case ProviderType.novel:
        // No trailer source for reading types.
        return null;
    }
  }

  /// Fetches all available trailers for the title (e.g. for a horizontal trailer carousel).
  Future<List<TrailerInfo>> fetchAllTrailers({
    required String title,
    String? englishTitle,
    required ProviderType type,
    String? year,
    int? tmdbId,
    bool? isTv,
  }) async {
    if (type == ProviderType.anime) {
      final ytId = await _anilistTrailer(title: title, englishTitle: englishTitle);
      if (ytId != null && ytId.isNotEmpty) {
        return [TrailerInfo(key: ytId, name: 'Official Trailer')];
      }
      return const [];
    }
    if (type != ProviderType.movie) return const [];

    try {
      String? resolvedId;
      String? mediaType;
      if (tmdbId != null && tmdbId > 0) {
        resolvedId = tmdbId.toString();
        mediaType = (isTv ?? false) ? 'tv' : 'movie';
      } else {
        final rawQuery = (englishTitle != null && englishTitle.isNotEmpty) ? englishTitle : title;
        final cleaned = cleanTitle(rawQuery);
        final query = cleaned.isNotEmpty ? cleaned : rawQuery;
        final search = await _dio.get<dynamic>(
          '$_tmdbBase/search/multi',
          queryParameters: {'query': query},
        );
        final results = _asList(_asMap(search.data)?['results']);
        if (results != null && results.isNotEmpty) {
          final candidates = results
              .map(_asMap)
              .whereType<Map<String, dynamic>>()
              .where((r) {
                final mt = r['media_type']?.toString();
                return mt == 'movie' || mt == 'tv';
              })
              .toList();
          if (candidates.isNotEmpty) {
            Map<String, dynamic> picked = candidates.first;
            if (year != null && year.isNotEmpty) {
              for (final r in candidates) {
                if (_tmdbYear(r) == year) {
                  picked = r;
                  break;
                }
              }
            }
            mediaType = picked['media_type']?.toString();
            resolvedId = picked['id']?.toString();
          }
        }
      }

      if (resolvedId == null || mediaType == null) return const [];

      final videos = await _dio.get<dynamic>('$_tmdbBase/$mediaType/$resolvedId/videos');
      final vids = _asList(_asMap(videos.data)?['results'])
          ?.map(_asMap)
          .whereType<Map<String, dynamic>>()
          .where((v) => v['site']?.toString() == 'YouTube')
          .toList();
      if (vids == null || vids.isEmpty) return const [];

      final out = <TrailerInfo>[];
      for (final v in vids) {
        final key = v['key']?.toString();
        if (key != null && key.isNotEmpty) {
          out.add(TrailerInfo(
            key: key,
            name: v['name']?.toString() ?? 'Trailer',
            type: v['type']?.toString() ?? 'Trailer',
            site: 'YouTube',
          ));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // ── Direct stream extraction (youtube_explode_dart) ───────────────────────

  /// Resolves a YouTube video [youtubeId] to a direct, muxed (video+audio)
  /// stream URL that media_kit can play natively — no iframe, no YouTube
  /// chrome. Returns null when extraction fails (then the caller falls back to
  /// the static cover / a "trailer unavailable" message).
  ///
  /// Muxed streams from YouTube cap at ~360p, which is exactly what we want:
  ///   • [low] = true  → the LOWEST muxed quality, a light stream for the
  ///     autoplaying hero banner (cover-fitted, so the crop hides the low res).
  ///   • [low] = false → the muxed stream with the HIGHEST bitrate, the best
  ///     available for the fullscreen trailer.
  ///
  /// NOTE: googlevideo URLs are short-lived and can vary by region — resolve
  /// them fresh each time you want to play (the hero / fullscreen do exactly
  /// that), never persist them.
  Future<String?> streamUrl(String youtubeId, {bool low = false}) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(youtubeId);
      final muxed = manifest.muxed; // mp4 video+audio
      if (muxed.isNotEmpty) {
        final pick = low
            ? muxed.sortByVideoQuality().last
            : muxed.withHighestBitrate();
        return pick.url.toString();
      }
      // Modern YouTube fallback: videos often only expose separate video/audio
      // adaptive streams. For muted hero banners or lightweight preview, use videoOnly.
      final allVideo = manifest.videoOnly.toList();
      if (allVideo.isNotEmpty) {
        final mp4 = allVideo.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
        final list = mp4.isNotEmpty ? mp4 : allVideo;
        list.sort((a, b) => a.videoResolution.height.compareTo(b.videoResolution.height));
        return low ? list.first.url.toString() : list.last.url.toString();
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
  }

  /// HD variant of [streamUrl]: resolves a VIDEO-ONLY stream up to 1080p plus a
  /// best AUDIO-ONLY stream. YouTube only offers anything above ~720p as
  /// separate adaptive streams, so the caller plays [video] and attaches
  /// [audio] as an external track (mpv `audio-add`). Returns null when the
  /// video has no adaptive streams or extraction fails — the caller then falls
  /// back to [streamUrl] (the light muxed 360p). Same short-lived-URL rule:
  /// resolve fresh, never persist.
  Future<({String video, String audio})?> streamUrlHd(String youtubeId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(youtubeId);
      final allVideo = manifest.videoOnly.toList();
      final audioOnly = manifest.audioOnly;
      if (allVideo.isEmpty || audioOnly.isEmpty) return null;

      // Prefer MP4 (H.264) for broad hardware decoder support
      final mp4Video = allVideo.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      final videoOnly = mp4Video.isNotEmpty ? mp4Video : allVideo;

      videoOnly.sort(
        (a, b) => b.videoResolution.height.compareTo(a.videoResolution.height),
      );
      final atMost1080 =
          videoOnly.where((s) => s.videoResolution.height <= 1080);
      final video = atMost1080.isNotEmpty ? atMost1080.first : videoOnly.last;
      final audio = audioOnly.withHighestBitrate();
      return (video: video.url.toString(), audio: audio.url.toString());
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
  }

  // ── Anime: AniList GraphQL ────────────────────────────────────────────────

  Future<String?> _anilistTrailer({
    required String title,
    String? englishTitle,
  }) async {
    final search = (englishTitle != null && englishTitle.isNotEmpty)
        ? englishTitle
        : title;
    try {
      final res = await _dio.post<dynamic>(
        _anilistEndpoint,
        data: {
          'query': _anilistQuery,
          'variables': {'search': search},
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );
      final data = _asMap(res.data);
      final media = _asMap(_asMap(data?['data'])?['Media']);
      final trailer = _asMap(media?['trailer']);
      if (trailer == null) return null;
      final site = trailer['site']?.toString().toLowerCase();
      final id = trailer['id']?.toString();
      if (site == 'youtube' && id != null && id.isNotEmpty) return id;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Movie/TV: TMDB ────────────────────────────────────────────────────────

  Future<String?> _tmdbTrailer({
    required String title,
    String? englishTitle,
    String? year,
    int? tmdbId,
    bool? isTv,
  }) async {
    // 1. Direct TMDB ID lookup if known (100% reliable, zero ambiguity)
    if (tmdbId != null && tmdbId > 0) {
      final primaryType = (isTv == true) ? 'tv' : 'movie';
      final directKey = await _fetchTmdbVideos(primaryType, tmdbId.toString());
      if (directKey != null && directKey.isNotEmpty) return directKey;

      final fallbackType = primaryType == 'tv' ? 'movie' : 'tv';
      final fallbackKey = await _fetchTmdbVideos(fallbackType, tmdbId.toString());
      if (fallbackKey != null && fallbackKey.isNotEmpty) return fallbackKey;
    }

    // 2. Fallback to TMDB multi-search with title cleaning
    final rawQuery = (englishTitle != null && englishTitle.isNotEmpty)
        ? englishTitle
        : title;
    final cleaned = cleanTitle(rawQuery);
    final query = cleaned.isNotEmpty ? cleaned : rawQuery;

    try {
      final search = await _dio.get<dynamic>(
        '$_tmdbBase/search/multi',
        queryParameters: {'query': query},
      );
      final results = _asList(_asMap(search.data)?['results']);
      if (results == null || results.isEmpty) return null;

      // Keep only movie/tv results, then prefer one whose release year matches.
      final candidates = results
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .where((r) {
            final mt = r['media_type']?.toString();
            return mt == 'movie' || mt == 'tv';
          })
          .toList();
      if (candidates.isEmpty) return null;

      Map<String, dynamic> picked = candidates.first;
      if (year != null && year.isNotEmpty) {
        for (final r in candidates) {
          if (_tmdbYear(r) == year) {
            picked = r;
            break;
          }
        }
      }

      final mediaType = picked['media_type']?.toString();
      final id = picked['id']?.toString();
      if (id == null || id.isEmpty || mediaType == null) return null;

      return _fetchTmdbVideos(mediaType, id);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchTmdbVideos(String mediaType, String id) async {
    try {
      final videos = await _dio.get<dynamic>(
        '$_tmdbBase/$mediaType/$id/videos',
      );
      final vids = _asList(_asMap(videos.data)?['results'])
          ?.map(_asMap)
          .whereType<Map<String, dynamic>>()
          .where((v) => v['site']?.toString() == 'YouTube')
          .toList();
      if (vids == null || vids.isEmpty) return null;

      // Prefer Trailer, then Teaser, then any YouTube video.
      Map<String, dynamic>? best;
      for (final v in vids) {
        if (v['type']?.toString() == 'Trailer') {
          best = v;
          break;
        }
      }
      best ??= vids.firstWhere(
        (v) => v['type']?.toString() == 'Teaser',
        orElse: () => vids.first,
      );
      final key = best['key']?.toString();
      if (key != null && key.isNotEmpty) return key;
    } catch (_) {}
    return null;
  }

  /// Year from a TMDB result's release_date (movie) or first_air_date (tv).
  static String? _tmdbYear(Map<String, dynamic> r) {
    final date = (r['release_date'] ?? r['first_air_date'])?.toString() ?? '';
    if (date.length >= 4) return date.substring(0, 4);
    return null;
  }

  // ── tiny JSON helpers (defensive against dynamic shapes) ──────────────────

  static Map<String, dynamic>? _asMap(dynamic v) => v is Map<String, dynamic>
      ? v
      : (v is Map ? Map<String, dynamic>.from(v) : null);

  static List<dynamic>? _asList(dynamic v) => v is List ? v : null;
}
