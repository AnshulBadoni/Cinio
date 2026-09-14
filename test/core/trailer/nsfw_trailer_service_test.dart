import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/trailer/trailer_service.dart';

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

void main() {
  group('NsfwTrailerService - URL construction and normalization', () {
    test('normalizes model URLs correctly', () {
      final ctx1 = TrailerAlternateContext.model('Abella Danger');
      expect(
        NsfwTrailerService.buildListingUrl(ctx1),
        'https://pornstar-scenes.com/model/Abella%20Danger/AllScenes/',
      );

      final ctx2 = TrailerAlternateContext.model('  Abella-Danger  ');
      expect(
        NsfwTrailerService.buildListingUrl(ctx2),
        'https://pornstar-scenes.com/model/Abella%20Danger/AllScenes/',
      );
    });

    test('normalizes studio URLs correctly', () {
      final ctx1 = TrailerAlternateContext.studio('Tushy Raw');
      expect(
        NsfwTrailerService.buildListingUrl(ctx1),
        'https://pornstar-scenes.com/showcase/Tushy%20Raw/',
      );

      final ctx2 = TrailerAlternateContext.studio('Tushy-Raw');
      expect(
        NsfwTrailerService.buildListingUrl(ctx2),
        'https://pornstar-scenes.com/showcase/Tushy%20Raw/',
      );
    });

    test('retains required browser headers', () {
      expect(NsfwTrailerService.kDefaultHeaders['User-Agent'], contains('Mozilla/5.0'));
      expect(NsfwTrailerService.kDefaultHeaders['Referer'], 'https://pornstar-scenes.com/');
      expect(NsfwTrailerService.kDefaultHeaders['Origin'], 'https://pornstar-scenes.com');
    });
  });

  group('NsfwTrailerService - Extraction', () {
    test('returns null for empty name', () async {
      final service = NsfwTrailerService();
      final result = await service.fetch(
        context: const TrailerAlternateContext.model('   '),
      );
      expect(result, isNull);
    });

    test('successfully extracts first scene and HLS .m3u8 playlist', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) async {
        final path = options.uri.toString();
        if (path.contains('/model/Abella%20Danger/AllScenes/')) {
          const html = '''
            <html>
              <body>
                <div class="video-grid">
                  <a href="/video/Hotel_Vixen_Season_3_Episode_7/i12345/">Scene 1</a>
                  <a href="/video/Another_Scene/i67890/">Scene 2</a>
                </div>
              </body>
            </html>
          ''';
          return ResponseBody.fromString(html, 200, headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          });
        }

        if (path.contains('/video/Hotel_Vixen_Season_3_Episode_7/i12345/')) {
          const html = '''
            <html>
              <script>
                var videoUrl = "https://cdn.stream.example.com/hls/video_master.m3u8?token=xyz";
              </script>
            </html>
          ''';
          return ResponseBody.fromString(html, 200, headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          });
        }

        return ResponseBody.fromString('Not Found', 404);
      });

      final service = NsfwTrailerService(dio);
      final result = await service.fetch(
        context: const TrailerAlternateContext.model('Abella Danger'),
      );

      expect(result, isNotNull);
      expect(
        result!.url,
        'https://cdn.stream.example.com/hls/video_master.m3u8?token=xyz',
      );
      expect(result.headers['User-Agent'], isNotEmpty);
      expect(result.headers['Referer'], 'https://pornstar-scenes.com/');
      expect(result.headers['Origin'], 'https://pornstar-scenes.com');
    });

    test('returns null when no scene is found in listing', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) async {
        return ResponseBody.fromString('<html><body>No videos</body></html>', 200);
      });

      final service = NsfwTrailerService(dio);
      final result = await service.fetch(
        context: const TrailerAlternateContext.studio('Empty Studio'),
      );

      expect(result, isNull);
    });

    test('returns null when no .m3u8 is found on scene page', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) async {
        final path = options.uri.toString();
        if (path.contains('/showcase/')) {
          return ResponseBody.fromString(
            '<a href="/video/sample_scene/123/">Watch</a>',
            200,
          );
        }
        return ResponseBody.fromString(
          '<html><body>No m3u8 playlist here</body></html>',
          200,
        );
      });

      final service = NsfwTrailerService(dio);
      final result = await service.fetch(
        context: const TrailerAlternateContext.studio('Sample Studio'),
      );

      expect(result, isNull);
    });

    test('handles HTTP error gracefully without throwing', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) async {
        throw DioException(
          requestOptions: options,
          error: 'Connection refused',
          type: DioExceptionType.connectionError,
        );
      });

      final service = NsfwTrailerService(dio);
      final result = await service.fetch(
        context: const TrailerAlternateContext.model('Abella Danger'),
      );

      expect(result, isNull);
    });
  });

  group('TrailerService.resolveTrailer', () {
    test('returns direct TrailerSource when alternate NSFW trailer resolves', () async {
      final dio = Dio();
      final nsfwDio = Dio();
      nsfwDio.httpClientAdapter = _FakeAdapter((options) async {
        final path = options.uri.toString();
        if (path.contains('/model/')) {
          return ResponseBody.fromString(
            '<a href="/video/test_scene/1/">Scene</a>',
            200,
          );
        }
        return ResponseBody.fromString(
          'https://cdn.example.com/master.m3u8',
          200,
        );
      });

      final nsfwService = NsfwTrailerService(nsfwDio);
      final trailerService = TrailerService(dio, nsfwService);

      final result = await trailerService.resolveTrailer(
        title: 'Abella Danger',
        type: ProviderType.movie,
        alternateContext: const TrailerAlternateContext.model('Abella Danger'),
      );

      expect(result, isNotNull);
      expect(result!.isDirect, isTrue);
      expect(result.directUrl, 'https://cdn.example.com/master.m3u8');
      expect(result.headers?['Referer'], 'https://pornstar-scenes.com/');
    });

    test('falls back to normal trailer when alternate NSFW lookup fails', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) async {
        final path = options.uri.toString();
        if (path.contains('/search/multi')) {
          return ResponseBody.fromString(
            '{"results":[{"id":123,"media_type":"movie"}]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (path.contains('/movie/123/videos')) {
          return ResponseBody.fromString(
            '{"results":[{"site":"YouTube","type":"Trailer","key":"dQw4w9WgXcQ"}]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
      });

      final nsfwDio = Dio();
      nsfwDio.httpClientAdapter = _FakeAdapter((options) async {
        return ResponseBody.fromString('<html>No scenes</html>', 200);
      });

      final nsfwService = NsfwTrailerService(nsfwDio);
      final trailerService = TrailerService(dio, nsfwService);

      final result = await trailerService.resolveTrailer(
        title: 'Some Movie',
        type: ProviderType.movie,
        alternateContext: const TrailerAlternateContext.model('Some Model'),
      );

      expect(result, isNotNull);
      expect(result!.isYoutube, isTrue);
      expect(result.youtubeId, 'dQw4w9WgXcQ');
    });

    test('does not query NSFW source when alternateContext is null', () async {
      bool nsfwCalled = false;
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) async {
        final path = options.uri.toString();
        if (path.contains('/search/multi')) {
          return ResponseBody.fromString(
            '{"results":[{"id":999,"media_type":"movie"}]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (path.contains('/movie/999/videos')) {
          return ResponseBody.fromString(
            '{"results":[{"site":"YouTube","type":"Trailer","key":"abc123xyz"}]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
      });

      final nsfwDio = Dio();
      nsfwDio.httpClientAdapter = _FakeAdapter((options) async {
        nsfwCalled = true;
        return ResponseBody.fromString('{}', 200);
      });

      final nsfwService = NsfwTrailerService(nsfwDio);
      final trailerService = TrailerService(dio, nsfwService);

      final result = await trailerService.resolveTrailer(
        title: 'Standard Movie',
        type: ProviderType.movie,
        alternateContext: null,
      );

      expect(nsfwCalled, isFalse);
      expect(result, isNotNull);
      expect(result!.isYoutube, isTrue);
      expect(result.youtubeId, 'abc123xyz');
    });
  });
}
