import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/provider_info.dart';
import '../models/media_detail.dart';

class TrailerSource {
  final String? youtubeId;
  final String? url;
  final Map<String, String> headers;

  const TrailerSource.youtube(String id)
      : youtubeId = id,
        url = null,
        headers = const {};

  const TrailerSource.direct(String url, {Map<String, String> headers = const {}})
      : youtubeId = null,
        url = url,
        headers = headers;

  bool get isDirect => url != null && url!.isNotEmpty;
}

/// Resolves a YouTube trailer id for a title from a metadata provider.
///
/// Streaming sources (AllAnime / NetMirror) don't expose trailers, so we match
/// the title against a free/keyed metadata API and pull its YouTube trailer:
///   • Anime  → AniList GraphQL (free, no key).
///   • Movie/TV → TMDB (key-gated; gracefully disabled when [kTmdbApiKey] is
///     empty).
///
/// Best-effort and cheap: every lookup is wrapped so any network/parse failure
/// resolves to `null` rather than throwing — the caller just hides the button.
class TrailerService {
  TrailerService(this._dio);
  final Dio _dio;

  static const String _anilistEndpoint = 'https://graphql.anilist.co';
  // TMDB v3 — api_key attached by the Dio interceptor (initDependencies).
  static const String _tmdbBase = 'https://api.themoviedb.org/3';

  static const String _anilistQuery =
      'query(\$search:String){ Media(search:\$search, type:ANIME){ '
      'id title{romaji english} trailer{ id site } } }';

  /// Resolves the preferred trailer source. Provider-supplied trailers always
  /// win when they contain a non-empty URL; metadata fallback is used only when
  /// the provider did not supply one.
  Future<TrailerSource?> resolve({
    required String title,
    String? englishTitle,
    required ProviderType type,
    String? year,
    List<ProviderTrailer> providerTrailers = const [],
  }) async {
    for (final trailer in providerTrailers) {
      final url = trailer.url.trim();
      if (url.isEmpty) continue;
      final providerYoutubeId = _youtubeIdFromUrl(url);
      if (providerYoutubeId != null) {
        return TrailerSource.youtube(providerYoutubeId);
      }
      return TrailerSource.direct(url, headers: trailer.headers);
    }
    final id = await youtubeId(
      title: title,
      englishTitle: englishTitle,
      type: type,
      year: year,
    );
    return id == null || id.isEmpty ? null : TrailerSource.youtube(id);
  }


  static String? _youtubeIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be' || host.endsWith('.youtube.com') || host == 'youtube.com') {
      if (host == 'youtu.be') {
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        return id?.isNotEmpty == true ? id : null;
      }
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
      final match = RegExp(r'^/(?:embed|shorts|live)/([^/?]+)').firstMatch(uri.path);
      return match?.group(1);
    }
    return null;
  }

  /// Returns a YouTube video id for the title, or null. Cheap + best-effort.
  Future<String?> youtubeId({
    required String title,
    String? englishTitle,
    required ProviderType type,
    String? year,
  }) async {
    switch (type) {
      case ProviderType.anime:
        return _anilistTrailer(title: title, englishTitle: englishTitle);
      case ProviderType.movie:
        return _tmdbTrailer(
          title: title,
          englishTitle: englishTitle,
          year: year,
        );
      case ProviderType.manga:
      case ProviderType.novel:
        // No trailer source for reading types.
        return null;
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
      if (muxed.isEmpty) return null;
      // sortByVideoQuality() is descending (best first), so .last is the
      // lowest muxed quality — the light pick for the banner.
      final pick = low
          ? muxed.sortByVideoQuality().last
          : muxed.withHighestBitrate();
      return pick.url.toString();
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
      final videoOnly = manifest.videoOnly.toList();
      final audioOnly = manifest.audioOnly;
      if (videoOnly.isEmpty || audioOnly.isEmpty) return null;
      // Highest quality at or below 1080p (a trailer doesn't need 1440/4K);
      // if nothing is ≤1080p, take the lowest available (closest to 1080).
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
  }) async {
    final query = (englishTitle != null && englishTitle.isNotEmpty)
        ? englishTitle
        : title;
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
      return null;
    } catch (_) {
      return null;
    }
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
