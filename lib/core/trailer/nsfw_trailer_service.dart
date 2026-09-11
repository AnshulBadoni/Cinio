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

/// Scrapes NSFW trailers from pornstar-scenes.com for model and studio contexts.
///
/// Execution is lazy, best-effort, and fails safely to null without crashing.
class NsfwTrailerService {
  NsfwTrailerService([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _baseUrl = 'https://pornstar-scenes.com';

  static const Map<String, String> kDefaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://pornstar-scenes.com/',
    'Origin': 'https://pornstar-scenes.com',
  };

  static final RegExp _sceneHrefRegex = RegExp(
    r'''href=['"](/video/[^'"]+)['"]''',
    caseSensitive: false,
  );

  static final RegExp _m3u8Regex = RegExp(
    r'''https?://[^\\'"\s<>]+\.m3u8[^\\'"\s<>]*''',
    caseSensitive: false,
  );

  /// Normalizes a name string: trims, replaces hyphens with spaces, collapses
  /// repeated whitespace, and URL-encodes with `%20` for spaces.
  static String normalizeName(String name) {
    final cleaned = name
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return Uri.encodeComponent(cleaned);
  }

  /// Builds the listing URL for the given [context].
  static String buildListingUrl(TrailerAlternateContext context) {
    final encoded = normalizeName(context.name);
    return switch (context.type) {
      TrailerAlternateType.model => '$_baseUrl/model/$encoded/AllScenes/',
      TrailerAlternateType.studio => '$_baseUrl/showcase/$encoded/',
    };
  }

  /// Fetches an alternate trailer for the given [context].
  /// Returns null if no scenes or .m3u8 streams are found, or on network/parse error.
  Future<AlternateTrailer?> fetch({
    required TrailerAlternateContext context,
  }) async {
    if (context.name.trim().isEmpty) return null;

    try {
      final listingUrl = buildListingUrl(context);

      // Step 1: Fetch listing page
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

      // Step 2: Find the first scene href
      final sceneMatch = _sceneHrefRegex.firstMatch(listingHtml);
      var videoPath = sceneMatch?.group(1);
      if (videoPath == null || videoPath.isEmpty) return null;

      final String sceneUrl;
      if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
        sceneUrl = videoPath;
      } else {
        if (!videoPath.startsWith('/')) videoPath = '/$videoPath';
        sceneUrl = '$_baseUrl$videoPath';
      }

      // Step 3: Fetch scene page
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
      final m3u8Url = m3u8Match?.group(0);
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
