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
        'https://www.adultempire.com/allsearch/search?q=Abella%20Danger',
      );

      final ctx2 = TrailerAlternateContext.model('  Abella-Danger  ');
      expect(
        NsfwTrailerService.buildListingUrl(ctx2),
        'https://www.adultempire.com/allsearch/search?q=Abella%20Danger',
      );
    });

    test('normalizes studio URLs correctly', () {
      final ctx1 = TrailerAlternateContext.studio('Tushy Raw');
      expect(
        NsfwTrailerService.buildListingUrl(ctx1),
        'https://www.adultempire.com/allsearch/search?q=Tushy%20Raw',
      );

      final ctx2 = TrailerAlternateContext.studio('Tushy-Raw');
      expect(
        NsfwTrailerService.buildListingUrl(ctx2),
        'https://www.adultempire.com/allsearch/search?q=Tushy%20Raw',
      );
    });

    test('normalizes movie URLs correctly', () {
      final ctx1 = TrailerAlternateContext.movie('Let Me In Too');
      expect(
        NsfwTrailerService.buildListingUrl(ctx1),
        'https://www.adultempire.com/allsearch/search?q=Let%20Me%20In%20Too',
      );
    });

    test('retains required browser headers', () {
      expect(NsfwTrailerService.kDefaultHeaders['User-Agent'], contains('Mozilla/5.0'));
      expect(NsfwTrailerService.kDefaultHeaders['Referer'], 'https://www.adultempire.com/');
      expect(NsfwTrailerService.kDefaultHeaders['Origin'], 'https://www.adultempire.com');
      expect(NsfwTrailerService.kDefaultHeaders['Cookie'], contains('ageConfirmed=true'));
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
        if (path.contains('/allsearch/search?q=Abella%20Danger')) {
          const html = '''
            <html>
              <body>
                <div class="video-grid">
                  <a href="/12345/hotel-vixen-episode-7.html">Scene 1</a>
                  <a href="/67890/another-scene.html">Scene 2</a>
                </div>
              </body>
            </html>
          ''';
          return ResponseBody.fromString(html, 200, headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          });
        }

        if (path.contains('/12345/hotel-vixen-episode-7.html')) {
          const html = '''
            <html>
              <script>
                var videoUrl = "https://video.adultempire.com/hls/previewmovie/12345/index-f1-v1.m3u8";
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
        'https://video.adultempire.com/hls/previewmovie/12345/index-f1-v1.m3u8',
      );
      expect(result.headers['User-Agent'], isNotEmpty);
      expect(result.headers['Referer'], 'https://www.adultempire.com/');
      expect(result.headers['Origin'], 'https://www.adultempire.com');
      expect(result.headers['Cookie'], contains('ageConfirmed=true'));
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
        if (path.contains('/allsearch/search')) {
          return ResponseBody.fromString(
            '<a href="/12345/sample-scene.html">Watch</a>',
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
        if (path.contains('/allsearch/search')) {
          return ResponseBody.fromString(
            '<a href="/12345/test-scene.html">Scene</a>',
            200,
          );
        }
        return ResponseBody.fromString(
          'https://video.adultempire.com/hls/previewmovie/12345/index-f1-v1.m3u8',
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
      expect(result.directUrl, 'https://video.adultempire.com/hls/previewmovie/12345/index-f1-v1.m3u8');
      expect(result.headers?['Referer'], 'https://www.adultempire.com/');
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
