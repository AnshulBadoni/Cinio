import 'package:dio/dio.dart';

/// Context type for alternate NSFW trailer resolution.
enum TrailerAlternateType { model, studio, movie }

/// Context payload holding the type and name for alternate trailer resolution.
class TrailerAlternateContext {
  const TrailerAlternateContext.model(this.name)
      : type = TrailerAlternateType.model;

  const TrailerAlternateContext.studio(this.name)
      : type = TrailerAlternateType.studio;

  const TrailerAlternateContext.movie(this.name)
      : type = TrailerAlternateType.movie;

  const TrailerAlternateContext({
    required this.type,
    required this.name,
  });

  final TrailerAlternateType type;
  final String name;

  bool get isModel => type == TrailerAlternateType.model;
  bool get isStudio => type == TrailerAlternateType.studio;
  bool get isMovie => type == TrailerAlternateType.movie;

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

/// Scrapes NSFW trailers from adultempire.com for model, studio, and movie contexts.
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
    r'''data-(?:movie|clip|item)-id=['"](\d+)['"]|/(?:(\d+)/)''',
    caseSensitive: false,
  );

  static final RegExp _sceneIdRegex = RegExp(
    r'''data-scene-id=['"](\d+)['"]''',
    caseSensitive: false,
  );

  static final RegExp _clipIdRegex = RegExp(
    r'''data-clip-id=['"](\d+)['"]''',
    caseSensitive: false,
  );

  static final RegExp _videoStreamRegex = RegExp(
    r'''https?://[^\\'"\s<>]+\.(?:m3u8|mp4)[^\\'"\s<>]*''',
    caseSensitive: false,
  );

  static final RegExp _videoTagSrcRegex = RegExp(
    r'''<(?:source|video)[^>]+src=['"]([^'"]+)['"]''',
    caseSensitive: false,
  );

  /// Normalizes a name string: trims, replaces hyphens with spaces, collapses
  /// repeated whitespace, and URL-encodes with standard percent encoding.
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
  /// Returns null if no scenes or video streams are found, or on network/parse error.
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

      // Check if direct video stream is already embedded in listing
      final directStream = _videoStreamRegex.firstMatch(listingHtml)?.group(0);
      if (directStream != null && directStream.isNotEmpty) {
        return AlternateTrailer(
          url: directStream,
          headers: Map<String, String>.unmodifiable(kDefaultHeaders),
        );
      }

      // Step 2: Find the first movie or scene href (ignoring shop/category/toys links)
      final allMatches = <String>[];
      for (final m in _itemHrefRegex.allMatches(listingHtml)) {
        final path = m.group(1);
        if (path != null) allMatches.add(path);
      }
      for (final m in _videoHrefRegex.allMatches(listingHtml)) {
        final path = m.group(1);
        if (path != null) allMatches.add(path);
      }

      final validMatches = allMatches.where((p) {
        final lower = p.toLowerCase();
        return !lower.contains('/category/') &&
            !lower.contains('/stores/') &&
            !lower.contains('/toys/') &&
            !lower.contains('/sex-toys') &&
            !lower.contains('/novelties/') &&
            !lower.contains('/cart') &&
            !lower.contains('/login');
      }).toList();

      var videoPath = validMatches.firstWhere(
        (p) =>
            p.contains('-porn-movies') ||
            p.contains('-porn-videos') ||
            p.contains('/movie/') ||
            p.contains('/scene/') ||
            p.contains('/video/'),
        orElse: () => validMatches.isNotEmpty ? validMatches.first : '',
      );

      String? movieId;
      final movieMatchInPath = RegExp(r'/(\d+)/').firstMatch(videoPath);
      if (movieMatchInPath != null) {
        movieId = movieMatchInPath.group(1);
      }

      if (videoPath.isEmpty) {
        final movieIdMatch = _movieIdRegex.firstMatch(listingHtml);
        movieId ??= movieIdMatch?.group(1);
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

      // Extract scene / movie / clip IDs from the scene page
      movieId ??= _movieIdRegex.firstMatch(sceneHtml)?.group(1);
      final sceneId = _sceneIdRegex.firstMatch(sceneHtml)?.group(1);
      final clipId = _clipIdRegex.firstMatch(sceneHtml)?.group(1);

      // Find video stream (.m3u8 or .mp4)
      final streamMatch = _videoStreamRegex.firstMatch(sceneHtml);
      var streamUrl = streamMatch?.group(0);

      if (streamUrl == null || streamUrl.isEmpty) {
        final tagMatch = _videoTagSrcRegex.firstMatch(sceneHtml);
        final tagSrc = tagMatch?.group(1);
        if (tagSrc != null && tagSrc.isNotEmpty) {
          streamUrl = tagSrc.startsWith('http') ? tagSrc : '$_baseUrl$tagSrc';
        }
      }

      if ((streamUrl == null || streamUrl.isEmpty) && movieId != null && movieId.isNotEmpty) {
        if (sceneId != null && sceneId.isNotEmpty) {
          streamUrl = 'https://video.adultempire.com/hls/previewscene/$movieId/$sceneId/index-f1-v1.m3u8';
        } else if (clipId != null && clipId.isNotEmpty) {
          streamUrl = 'https://video.adultempire.com/hls/previewclip/$movieId/$clipId/index-f1-v1.m3u8';
        }
      }

      if (streamUrl == null || streamUrl.isEmpty) return null;

      // Step 4: Return trailer source with playback headers
      return AlternateTrailer(
        url: streamUrl,
        headers: Map<String, String>.unmodifiable(kDefaultHeaders),
      );
    } catch (_) {
      return null;
    }
  }
}
