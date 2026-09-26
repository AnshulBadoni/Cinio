import 'dart:convert';
import 'package:dio/dio.dart';

import 'stremio_manifest.dart';
import 'stremio_stream.dart';

class StremioClient {
  StremioClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;

  /// Canonicalizes an addon URL. Handles:
  /// - `stremio://` -> `https://`
  /// - Missing `/manifest.json` -> adds `/manifest.json`
  static String canonicalizeManifestUrl(String url) {
    var u = url.trim();
    if (u.startsWith('stremio://')) {
      u = 'https://${u.substring('stremio://'.length)}';
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    if (!u.endsWith('/manifest.json')) {
      if (u.endsWith('/')) {
        u = '${u}manifest.json';
      } else {
        u = '$u/manifest.json';
      }
    }
    return u;
  }

  /// Extracts the base URL for resource calls by stripping `/manifest.json`.
  static String getBaseUrl(String manifestUrl) {
    final canon = canonicalizeManifestUrl(manifestUrl);
    if (canon.endsWith('/manifest.json')) {
      return canon.substring(0, canon.length - '/manifest.json'.length);
    }
    return canon;
  }

  /// Fetches and parses a Stremio manifest.
  Future<StremioManifest> getManifest(String url) async {
    final manifestUrl = canonicalizeManifestUrl(url);
    final res = await _dio.get<dynamic>(manifestUrl);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      return StremioManifest.fromJson(data);
    } else if (data is String) {
      final parsed = jsonDecode(data);
      if (parsed is Map<String, dynamic>) {
        return StremioManifest.fromJson(parsed);
      }
    }
    throw const FormatException('Invalid Stremio manifest response');
  }

  /// Fetches streams for an item from a Stremio addon.
  /// [baseUrl]: Base URL of the addon (without `/manifest.json`).
  /// [type]: 'movie' or 'series' (or 'anime').
  /// [id]: 'tt1234567' or 'tt1234567:1:1' or 'kitsu:123:1'.
  Future<List<StremioStream>> getStreams({
    required String baseUrl,
    required String type,
    required String id,
  }) async {
    try {
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final endpoint = '$cleanBase/stream/$type/$id.json';
      final res = await _dio.get<dynamic>(
        endpoint,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = res.data;
      final Map<String, dynamic> json;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is String) {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) {
          json = parsed;
        } else {
          return const [];
        }
      } else {
        return const [];
      }

      final rawStreams = json['streams'] as List? ?? const [];
      return rawStreams
          .whereType<Map<String, dynamic>>()
          .map((s) => StremioStream.fromJson(s))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches a catalog page from a Stremio addon.
  Future<List<Map<String, dynamic>>> getCatalog({
    required String baseUrl,
    required String type,
    required String id,
    int skip = 0,
    String? searchQuery,
  }) async {
    try {
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final parts = <String>['$cleanBase/catalog/$type/$id'];
      if (searchQuery != null && searchQuery.isNotEmpty) {
        parts.add('search=${Uri.encodeComponent(searchQuery)}.json');
      } else if (skip > 0) {
        parts.add('skip=$skip.json');
      } else {
        parts.add('.json');
      }

      final endpoint = parts.length == 2 && parts[1].startsWith('.')
          ? '${parts[0]}${parts[1]}'
          : '${parts[0]}/${parts[1]}';

      final res = await _dio.get<dynamic>(endpoint);
      final data = res.data;
      final Map<String, dynamic> json;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is String) {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) {
          json = parsed;
        } else {
          return const [];
        }
      } else {
        return const [];
      }

      final metas = json['metas'] as List? ?? const [];
      return metas.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
}
