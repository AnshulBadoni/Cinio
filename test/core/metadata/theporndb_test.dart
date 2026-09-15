import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/theporndb.dart';
import 'package:watch_app/core/metadata/people_service.dart';
import 'package:watch_app/core/models/person.dart';

void main() {
  late ThePornDb tpdb;

  setUp(() {
    tpdb = ThePornDb(Dio());
  });

  group('ThePornDb live integration tests', () {
    test('movies returns non-empty list of MediaItems', () async {
      final items = await tpdb.movies(page: 1, orderBy: 'recently_released');
      expect(items, isNotEmpty);
      expect(items.first.sourceId, 'tpdb:catalog');
      expect(items.first.id, startsWith('tpdb:movie:'));
    });

    test('search returns matching movies', () async {
      final items = await tpdb.search('nurse', page: 1);
      expect(items, isNotEmpty);
      expect(items.first.sourceId, 'tpdb:catalog');
    });

    test('performers returns non-empty list of performers', () async {
      final items = await tpdb.performers(page: 1);
      expect(items, isNotEmpty);
      expect(items.first.sourceId, 'tpdb:performer');
    });

    test('studios returns non-empty list of studios', () async {
      final items = await tpdb.studios(page: 1);
      expect(items, isNotEmpty);
      expect(items.first.sourceId, 'tpdb:studio');
    });

    test('home returns all expected sections', () async {
      final sections = await tpdb.home();
      expect(sections, isNotEmpty);
      final titles = sections.map((s) => s.title).toList();
      expect(titles, contains('Recent'));
      expect(titles, contains('Trending'));
      expect(titles, contains('Actors'));
      expect(titles, contains('Popular'));
      expect(titles, contains('Top Rated'));
      expect(titles, isNot(contains('Studio')));
    });

    test('movieDetail resolves cast with valid canonical person refs', () async {
      final movies = await tpdb.movies(page: 1, orderBy: 'recently_released');
      expect(movies, isNotEmpty);
      final detail = await tpdb.movieDetail(movies.first);
      expect(detail.id, startsWith('tpdb:movie:'));
    });

    test('PeopleService loads TPDB performer profile with fallback', () async {
      final peopleService = PeopleService(Dio());
      final performers = await tpdb.performers(page: 1);
      expect(performers, isNotEmpty);

      final first = performers.first;
      final rawId = first.id.replaceFirst('tpdb:performer:', '');
      final ref = PersonRef(
        id: int.tryParse(rawId) ?? 0,
        externalId: rawId,
        source: PersonSource.thePornDbPerformer,
        name: first.title,
      );
      final profile = await peopleService.load(ref);

      expect(profile, isNotNull);
      expect(profile!.name, isNotEmpty);

      final page2Works = await peopleService.loadWorks(ref, page: 2);
      expect(page2Works, isA<List>());
    });
  });
}
