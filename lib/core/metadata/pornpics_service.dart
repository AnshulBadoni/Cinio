import 'package:dio/dio.dart';

/// Fetches high-resolution performer portraits and photos from pornpics.de.
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

  /// Looks up a model/performer photo by name.
  /// First checks the direct performer page (entity-card-avatar),
  /// then falls back to searching pornpics search JSON.
  Future<String?> fetchModelPhoto(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return null;
    final key = cleanName.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];

    final slug = key
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    // 1. Direct performer model page: https://www.pornpics.de/pornstars/{slug}/
    if (slug.isNotEmpty) {
      try {
        final res = await _dio.get<String>(
          'https://www.pornpics.de/pornstars/$slug/',
        );
        if (res.statusCode == 200 && res.data != null) {
          final html = res.data!;
          // Pattern: <div class="entity-card-avatar" ...><img src="https://cdni.pornpics.de/models/..."
          final match = RegExp(
            r'<div class="entity-card-avatar"[^>]*>\s*<img[^>]+src="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(html);
          if (match != null) {
            final url = match.group(1);
            if (url != null && url.isNotEmpty) {
              _cache[key] = url;
              return url;
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
            final tUrl = item['t_url_460'] ?? item['t_url'];
            if (tUrl != null && tUrl.toString().isNotEmpty) {
              final photo = tUrl.toString();
              _cache[key] = photo;
              return photo;
            }
          }
        }
      }
    } catch (_) {}

    _cache[key] = null;
    return null;
  }
}
