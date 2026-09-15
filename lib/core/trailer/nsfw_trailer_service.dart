import 'package:dio/dio.dart';

/// Context type for alternate NSFW trailer resolution.
enum TrailerAlternateType { model, studio }

/// Context payload holding the type and name for alternate trailer resolution.
class TrailerAlternateContext {
  const TrailerAlternateContext.model(this.name)
      : type = TrailerAlternateType.model;

  const TrailerAlternateContext.studio(this.name)
      : type = TrailerAlternateType.studio;

  const TrailerAlternateContext({
    required this.type,
    required this.name,
  });

  final TrailerAlternateType type;
  final String name;

  bool get isModel => type == TrailerAlternateType.model;
  bool get isStudio => type == TrailerAlternateType.studio;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrailerAlternateContext &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          name == other.name;

  @override
  int get hashCode => type.hashCode ^ name.hashCode;
}

/// Resolved alternate trailer stream URL with required HTTP request headers.
class AlternateTrailer {
  const AlternateTrailer({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlternateTrailer &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;
}

/// Scrapes NSFW trailers from adultempire.com for model and studio contexts.
///
/// Execution is lazy, best-effort, and fails safely to null without crashing.
class NsfwTrailerService {
  NsfwTrailerService([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _baseUrl = 'https://www.adultempire.com';

  static const Map<String, String> kDefaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://www.adultempire.com/',
    'Origin': 'https://www.adultempire.com',
    'Cookie': 'ageConfirmed=true; hasAcceptedAgeConfirmation=true; RTA=1; enter=1',
  };

  static final RegExp _itemHrefRegex = RegExp(
    r'''href=['"](/(\d+)/[^'"]+)['"]''',
    caseSensitive: false,
  );

  static final RegExp _videoHrefRegex = RegExp(
    r'''href=['"](/[^'"]*?(?:scene|watch|video|movie)/[^'"]+)['"]''',
    caseSensitive: false,
  );

  static final RegExp _movieIdRegex = RegExp(
    r'''data-movie-id=['"](\d+)['"]''',
    caseSensitive: false,
  );

  static final RegExp _m3u8Regex = RegExp(
    r'''https?://[^\\'"\s<>]+\.m3u8[^\\'"\s<>]*''',
    caseSensitive: false,
  );

  /// Normalizes a name string: trims, replaces hyphens with spaces, collapses
  /// repeated whitespace, and URL-encodes with `%20` or standard percent encoding.
  static String normalizeName(String name) {
    final cleaned = name
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return Uri.encodeComponent(cleaned);
  }

  /// Builds the search/listing URL for the given [context].
  static String buildListingUrl(TrailerAlternateContext context) {
    final encoded = normalizeName(context.name);
    return '$_baseUrl/allsearch/search?q=$encoded';
  }

  /// Fetches an alternate trailer for the given [context].
  /// Returns null if no scenes or .m3u8 streams are found, or on network/parse error.
  Future<AlternateTrailer?> fetch({
    required TrailerAlternateContext context,
  }) async {
    if (context.name.trim().isEmpty) return null;

    try {
      final listingUrl = buildListingUrl(context);

      // Step 1: Fetch listing / search page
      final listingRes = await _dio.get<dynamic>(
        listingUrl,
        options: Options(
          headers: kDefaultHeaders,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
        ),
      );

      final listingHtml = listingRes.data?.toString();
      if (listingHtml == null || listingHtml.isEmpty) return null;

      // Check if direct m3u8 is already embedded in listing
      final directM3u8 = _m3u8Regex.firstMatch(listingHtml)?.group(0);
      if (directM3u8 != null && directM3u8.isNotEmpty) {
        return AlternateTrailer(
          url: directM3u8,
          headers: Map<String, String>.unmodifiable(kDefaultHeaders),
        );
      }

      // Step 2: Find the first movie or scene href
      final match = _itemHrefRegex.firstMatch(listingHtml) ??
          _videoHrefRegex.firstMatch(listingHtml);
      var videoPath = match?.group(1);

      if (videoPath == null || videoPath.isEmpty) {
        final movieIdMatch = _movieIdRegex.firstMatch(listingHtml);
        final movieId = movieIdMatch?.group(1);
        if (movieId != null && movieId.isNotEmpty) {
          return AlternateTrailer(
            url: 'https://video.adultempire.com/hls/previewmovie/$movieId/index-f1-v1.m3u8',
            headers: Map<String, String>.unmodifiable(kDefaultHeaders),
          );
        }
        return null;
      }

      final String sceneUrl;
      if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
        sceneUrl = videoPath;
      } else {
        if (!videoPath.startsWith('/')) videoPath = '/$videoPath';
        sceneUrl = '$_baseUrl$videoPath';
      }

      // Step 3: Fetch movie / scene page
      final sceneRes = await _dio.get<dynamic>(
        sceneUrl,
        options: Options(
          headers: kDefaultHeaders,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
        ),
      );

      final sceneHtml = sceneRes.data?.toString();
      if (sceneHtml == null || sceneHtml.isEmpty) return null;

      // Find HLS playlist (.m3u8)
      final m3u8Match = _m3u8Regex.firstMatch(sceneHtml);
      var m3u8Url = m3u8Match?.group(0);

      if (m3u8Url == null || m3u8Url.isEmpty) {
        final movieIdMatch = _movieIdRegex.firstMatch(sceneHtml);
        final movieId = movieIdMatch?.group(1);
        if (movieId != null && movieId.isNotEmpty) {
          m3u8Url = 'https://video.adultempire.com/hls/previewmovie/$movieId/index-f1-v1.m3u8';
        }
      }

      if (m3u8Url == null || m3u8Url.isEmpty) return null;

      // Step 4: Return trailer source with playback headers
      return AlternateTrailer(
        url: m3u8Url,
        headers: Map<String, String>.unmodifiable(kDefaultHeaders),
      );
    } catch (_) {
      return null;
    }
  }
}
