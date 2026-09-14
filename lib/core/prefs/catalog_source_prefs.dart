import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hive/safe_box.dart';

enum CatalogSource { provider, tmdb, thePornDb, mixed }

extension CatalogSourceLabel on CatalogSource {
  String get label => switch (this) {
        CatalogSource.provider => 'Provider',
        CatalogSource.tmdb => 'TMDB Only',
        CatalogSource.thePornDb => 'ThePornDB Only',
        CatalogSource.mixed => 'Mixed',
      };
}

class CatalogSourcePrefs extends ChangeNotifier {
  static const String boxName = 'catalog_source_prefs';
  static const String _key = 'source';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely(boxName);
  }

  Box get _box => Hive.box(boxName);

  CatalogSource get source {
    final raw = _box.get(_key, defaultValue: CatalogSource.provider.name);
    return CatalogSource.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => CatalogSource.provider,
    );
  }

  Future<void> setSource(CatalogSource value) async {
    await _box.put(_key, value.name);
    notifyListeners();
  }
}
