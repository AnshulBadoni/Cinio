import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/prefs/catalog_source_prefs.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalog_prefs_test');
    Hive.init(dir.path);
    await Hive.openBox(CatalogSourcePrefs.boxName);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('default section orders are returned when unset', () {
    final prefs = CatalogSourcePrefs();
    expect(prefs.getSectionOrder(CatalogSource.tmdb), CatalogSourcePrefs.defaultTmdbKinds);
    expect(prefs.getSectionOrder(CatalogSource.thePornDb), CatalogSourcePrefs.defaultTpdbKinds);
    expect(prefs.getSectionOrder(CatalogSource.mixed), CatalogSourcePrefs.defaultMixedKinds);
  });

  test('custom section order roundtrips and appends missing defaults', () async {
    final prefs = CatalogSourcePrefs();
    final customTpdb = [
      'tpdb_performers',
      'tpdb_top_rated',
      'tpdb_recent',
    ];
    await prefs.setSectionOrder(CatalogSource.thePornDb, customTpdb);

    final saved = prefs.getSectionOrder(CatalogSource.thePornDb);
    expect(saved.first, 'tpdb_performers');
    expect(saved[1], 'tpdb_top_rated');
    expect(saved[2], 'tpdb_recent');
    // Any remaining default kinds should be appended
    for (final def in CatalogSourcePrefs.defaultTpdbKinds) {
      expect(saved.contains(def), isTrue);
    }
  });

  test('resetSectionOrder restores default order', () async {
    final prefs = CatalogSourcePrefs();
    final customTmdb = [
      'tmdb_trending_anime',
      'tmdb_recent',
    ];
    await prefs.setSectionOrder(CatalogSource.tmdb, customTmdb);
    expect(prefs.getSectionOrder(CatalogSource.tmdb).first, 'tmdb_trending_anime');

    await prefs.resetSectionOrder(CatalogSource.tmdb);
    expect(prefs.getSectionOrder(CatalogSource.tmdb), CatalogSourcePrefs.defaultTmdbKinds);
  });
}
