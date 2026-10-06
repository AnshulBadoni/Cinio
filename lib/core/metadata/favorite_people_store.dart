import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/person.dart';
import '../storage/hive_storage.dart';

/// Local store for favorited actors and performers.
class FavoritePeopleStore {
  static const String boxName = 'favorite_people';

  static Future<void> init() async {
    await openBoxSafely<Map>(boxName);
  }

  Box<Map>? get _box => Hive.isBoxOpen(boxName) ? Hive.box<Map>(boxName) : null;

  static String keyFor(PersonRef ref) =>
      '${ref.source.name}:${ref.externalId ?? ref.id}';

  bool isFavorite(PersonRef ref) {
    return _box?.containsKey(keyFor(ref)) ?? false;
  }

  Future<void> toggleFavorite(PersonRef ref) async {
    final box = _box;
    if (box == null) return;
    final k = keyFor(ref);
    if (box.containsKey(k)) {
      await box.delete(k);
    } else {
      await box.put(k, {
        'id': ref.id,
        'source': ref.source.name,
        'name': ref.name,
        'photo': ref.photo,
        'externalId': ref.externalId,
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  List<PersonRef> allFavorites() {
    final box = _box;
    if (box == null) return const [];
    final list = <PersonRef>[];
    for (final raw in box.values) {
      if (raw is! Map) continue;
      final sourceStr = raw['source']?.toString() ?? '';
      final source = PersonSource.values.firstWhere(
        (s) => s.name == sourceStr,
        orElse: () => PersonSource.tmdb,
      );
      list.add(PersonRef(
        id: (raw['id'] as num?)?.toInt() ?? 0,
        source: source,
        name: raw['name']?.toString() ?? '',
        photo: raw['photo']?.toString(),
        externalId: raw['externalId']?.toString(),
      ));
    }
    return list;
  }

  ValueListenable<Box<Map>>? listenable() => _box?.listenable();
}
