import 'package:dio/dio.dart';

/// Fetches high-resolution performer portraits and photos from pornpics.de.
/// Extracts full-resolution catalog photos (1280px) instead of low-res header avatars.
class PornPicsService {
  PornPicsService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept': 'text/html,application/json,*/*',
                },
              ),
            );

  final Dio _dio;
  final Map<String, String?> _cache = {};

  /// Returns synchronous cached photo if already fetched.
  String? cachedPhoto(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    return _cache[clean.toLowerCase()];
  }

  /// Looks up a high-resolution performer photo by name from pornpics catalog galleries.
  /// 1. Scrapes the performer page for catalog gallery photos and upgrades to 1280px resolution.
  /// 2. Falls back to search endpoint JSON, also upgrading catalog items to 1280px resolution.
  Future<String?> fetchModelPhoto(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return null;
    final key = cleanName.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];

    final slug = key
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    // 1. Direct performer model page: https://www.pornpics.de/pornstars/{slug}/
    // Extract full-resolution catalog photos (upgraded to 1280px) rather than low-res header avatars.
    if (slug.isNotEmpty) {
      try {
        final res = await _dio.get<String>(
          'https://www.pornpics.de/pornstars/$slug/',
        );
        if (res.statusCode == 200 && res.data != null) {
          final html = res.data!;
          // Find catalog gallery thumbnails: https://cdni.pornpics.de/460/...
          final catalogMatches = RegExp(
            r'https://cdni\.pornpics\.de/460/[a-zA-Z0-9/_.-]+\.jpg',
            caseSensitive: false,
          ).allMatches(html);

          for (final m in catalogMatches) {
            final thumbUrl = m.group(0);
            if (thumbUrl != null && thumbUrl.isNotEmpty) {
              final hdUrl = thumbUrl.replaceAll('/460/', '/1280/');
              _cache[key] = hdUrl;
              return hdUrl;
            }
          }
        }
      } catch (_) {}
    }

    // 2. Fallback: Search endpoint JSON: https://www.pornpics.de/search/srch.php?q={name}
    try {
      final searchRes = await _dio.get(
        'https://www.pornpics.de/search/srch.php',
        queryParameters: {'q': cleanName},
      );
      if (searchRes.statusCode == 200 && searchRes.data is List) {
        final list = searchRes.data as List;
        for (final item in list) {
          if (item is Map) {
            final tUrl = (item['t_url_460'] ?? item['t_url'])?.toString();
            if (tUrl != null && tUrl.isNotEmpty) {
              // Upgrade to 1280px high-resolution catalog photo
              final hdUrl = tUrl.contains('/460/')
                  ? tUrl.replaceAll('/460/', '/1280/')
                  : tUrl;
              _cache[key] = hdUrl;
              return hdUrl;
            }
          }
        }
      }
    } catch (_) {}

    _cache[key] = null;
    return null;
  }
}
