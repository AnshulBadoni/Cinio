import 'dart:async';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import '../di/injector.dart';

class ImdbRatingService {
  ImdbRatingService([Dio? dio]) : _dio = dio ?? sl<Dio>();

  final Dio _dio;
  static const String boxName = 'imdb_ratings_cache';
  final Map<String, double> _memCache = {};

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<double>(boxName);
    }
  }

  Future<double?> getRating(String imdbId, {bool isTv = false}) async {
    final cleanId = imdbId.trim();
    if (!cleanId.startsWith('tt')) return null;

    if (_memCache.containsKey(cleanId)) {
      return _memCache[cleanId];
    }

    if (Hive.isBoxOpen(boxName)) {
      final cached = Hive.box<double>(boxName).get(cleanId);
      if (cached != null && cached > 0) {
        _memCache[cleanId] = cached;
        return cached;
      }
    }

    try {
      final type = isTv ? 'series' : 'movie';
      final res = await _dio.get<dynamic>(
        'https://v3-cinemeta.stremio.com/meta/$type/$cleanId.json',
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = res.data;
      if (data is Map && data['meta'] is Map) {
        final meta = data['meta'] as Map;
        final rawRating = meta['imdbRating']?.toString();
        if (rawRating != null) {
          final rating = double.tryParse(rawRating);
          if (rating != null && rating > 0) {
            _memCache[cleanId] = rating;
            if (Hive.isBoxOpen(boxName)) {
              await Hive.box<double>(boxName).put(cleanId, rating);
            }
            return rating;
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
