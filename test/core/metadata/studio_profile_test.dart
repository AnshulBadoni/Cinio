import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/metadata/people_service.dart';
import 'package:watch_app/core/models/person.dart';
import 'package:watch_app/core/prefs/catalog_source_prefs.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(dynamic data, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_studio_test_');
    Hive.init(tempDir.path);
    await CatalogSourcePrefs.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('CatalogSourcePrefs defaults tpdbFilterOldAndGay to true and persists changes', () async {
    final prefs = CatalogSourcePrefs();
    expect(prefs.tpdbFilterOldAndGay, isTrue);

    await prefs.setTpdbFilterOldAndGay(false);
    expect(prefs.tpdbFilterOldAndGay, isFalse);

    await prefs.setTpdbFilterOldAndGay(true);
    expect(prefs.tpdbFilterOldAndGay, isTrue);
  });

  test('PeopleService loads TMDB company profile and works', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter((options) async {
      final path = options.uri.path;
      if (path.contains('/company/174')) {
        return _jsonResponse({
          'id': 174,
          'name': 'Warner Bros. Pictures',
          'description': 'Major film production studio.',
          'headquarters': 'Burbank, California',
          'origin_country': 'US',
          'logo_path': '/warner.png',
        });
      } else if (path.contains('/discover/movie')) {
        return _jsonResponse({
          'results': [
            {
              'id': 101,
              'title': 'The Batman',
              'poster_path': '/batman.jpg',
              'backdrop_path': '/batman_backdrop.jpg',
              'vote_average': 7.8,
              'release_date': '2022-03-04',
            }
          ]
        });
      } else if (path.contains('/discover/tv')) {
        return _jsonResponse({
          'results': [
            {
              'id': 201,
              'name': 'Supernatural',
              'poster_path': '/spn.jpg',
              'backdrop_path': '/spn_backdrop.jpg',
              'vote_average': 8.3,
              'first_air_date': '2005-09-13',
            }
          ]
        });
      }
      return _jsonResponse({});
    });

    final service = PeopleService(dio);

    // Warner Bros. Pictures TMDB company id is 174
    final profile = await service.load(const PersonRef(
      id: 174,
      source: PersonSource.tmdbCompany,
      name: 'Warner Bros. Pictures',
    ));

    expect(profile, isNotNull);
    expect(profile!.name, contains('Warner Bros'));
    expect(profile.works, isNotEmpty);
    expect(profile.subtitle, contains('Studio'));
    expect(profile.photos, isNotEmpty);
  });

  test('PeopleService resolves TMDB company by name when id is 0', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter((options) async {
      final path = options.uri.path;
      if (path.contains('/search/company')) {
        return _jsonResponse({
          'results': [
            {
              'id': 420,
              'name': 'Marvel Studios',
              'logo_path': '/marvel.png',
            }
          ]
        });
      } else if (path.contains('/company/420')) {
        return _jsonResponse({
          'id': 420,
          'name': 'Marvel Studios',
          'description': 'MCU film production studio.',
          'headquarters': 'Burbank, California',
          'origin_country': 'US',
          'logo_path': '/marvel.png',
        });
      } else if (path.contains('/discover/movie')) {
        return _jsonResponse({
          'results': [
            {
              'id': 301,
              'title': 'Avengers: Endgame',
              'poster_path': '/endgame.jpg',
              'backdrop_path': '/endgame_backdrop.jpg',
              'vote_average': 8.4,
              'release_date': '2019-04-26',
            }
          ]
        });
      } else if (path.contains('/discover/tv')) {
        return _jsonResponse({
          'results': [
            {
              'id': 401,
              'name': 'Loki',
              'poster_path': '/loki.jpg',
              'backdrop_path': '/loki_backdrop.jpg',
              'vote_average': 8.2,
              'first_air_date': '2021-06-09',
            }
          ]
        });
      }
      return _jsonResponse({});
    });

    final service = PeopleService(dio);

    final profile = await service.load(const PersonRef(
      id: 0,
      source: PersonSource.tmdbCompany,
      name: 'Marvel Studios',
    ));

    expect(profile, isNotNull);
    expect(profile!.name, contains('Marvel Studios'));
    expect(profile.works, isNotEmpty);
    expect(profile.subtitle, contains('Studio'));
  });
}
