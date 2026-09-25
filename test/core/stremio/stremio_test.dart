import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/stremio/stremio_client.dart';
import 'package:watch_app/core/stremio/stremio_manifest.dart';
import 'package:watch_app/core/stremio/stremio_provider.dart';
import 'package:watch_app/core/stremio/stremio_store.dart';
import 'package:watch_app/core/stremio/stremio_stream.dart';

void main() {
  group('Stremio Manifest parsing', () {
    test('parses standard Torrentio manifest JSON', () {
      final json = {
        'id': 'org.stremio.torrentio',
        'name': 'Torrentio',
        'version': '1.0.12',
        'description': 'Provides torrent & Debrid streams for movies and series',
        'resources': ['stream', 'catalog'],
        'types': ['movie', 'series', 'anime'],
        'idPrefixes': ['tt', 'kitsu'],
        'catalogs': [
          {
            'type': 'movie',
            'id': 'top',
            'name': 'Top Movies',
          }
        ],
        'behaviorHints': {
          'p2p': true,
          'configurable': true,
        },
      };

      final manifest = StremioManifest.fromJson(json);
      expect(manifest.id, 'org.stremio.torrentio');
      expect(manifest.name, 'Torrentio');
      expect(manifest.version, '1.0.12');
      expect(manifest.supportsStreams, isTrue);
      expect(manifest.supportsCatalogs, isTrue);
      expect(manifest.supportsSubtitles, isFalse);
      expect(manifest.isP2p, isTrue);
      expect(manifest.catalogs.length, 1);
      expect(manifest.catalogs.first.name, 'Top Movies');
    });

    test('parses resource objects with specific types', () {
      final json = {
        'id': 'community.subtitles',
        'name': 'OpenSubtitles v3',
        'version': '3.0.0',
        'resources': [
          {
            'name': 'subtitles',
            'types': ['movie', 'series'],
            'idPrefixes': ['tt'],
          }
        ],
        'types': ['movie', 'series'],
      };

      final manifest = StremioManifest.fromJson(json);
      expect(manifest.supportsSubtitles, isTrue);
      expect(manifest.supportsStreams, isFalse);
      expect(manifest.supportsResource('subtitles', type: 'movie'), isTrue);
    });
  });

  group('Stremio Stream mapping', () {
    test('translates direct HTTPS stream with subtitles to VideoSource', () {
      final streamJson = {
        'url': 'https://debrid.stream.net/v/1080p/video.mp4',
        'name': 'Torrentio\n[RD+] 1080p',
        'title': 'Breaking.Bad.S01E01.1080p.BluRay.x264\n💾 2.1 GB 👤 45',
        'behaviorHints': {
          'headers': {
            'User-Agent': 'Cinio/2.2.14',
          },
        },
        'subtitles': [
          {
            'id': 'sub_en',
            'url': 'https://subtitles.org/en/sub.vtt',
            'lang': 'en',
          }
        ],
      };

      final stream = StremioStream.fromJson(streamJson);
      final vs = stream.toVideoSource(addonName: 'Torrentio');

      expect(vs, isNotNull);
      expect(vs!.url, 'https://debrid.stream.net/v/1080p/video.mp4');
      expect(vs.quality, '1080p');
      expect(vs.container, SourceContainer.mp4);
      expect(vs.headers?['User-Agent'], 'Cinio/2.2.14');
      expect(vs.subtitles.length, 1);
      expect(vs.subtitles.first.url, 'https://subtitles.org/en/sub.vtt');
      expect(vs.subtitles.first.format, 'vtt');
      expect(vs.label, contains('1080p'));
      expect(vs.label, contains('Breaking.Bad.S01E01'));
    });

    test('translates HLS 4K HDR stream correctly', () {
      final streamJson = {
        'url': 'https://media.server.org/live/4k/index.m3u8',
        'name': '4K HDR10+ Dolby Vision',
        'description': 'Multi Audio 5.1',
      };

      final stream = StremioStream.fromJson(streamJson);
      final vs = stream.toVideoSource(addonName: 'MediaFusion');

      expect(vs, isNotNull);
      expect(vs!.quality, '4K');
      expect(vs.container, SourceContainer.hls);
      expect(vs.label, contains('4K HDR10+'));
    });

    test('translates raw P2P torrent stream to magnet VideoSource', () {
      final streamJson = {
        'infoHash': '4b8a1c9e827163f45d8b2e1a90c1f3a2b4e5d6c7',
        'name': 'Torrentio 1080p',
        'title': 'Movie.2024.1080p.WEB-DL',
      };

      final stream = StremioStream.fromJson(streamJson);
      final vs = stream.toVideoSource(addonName: 'Torrentio');

      expect(vs, isNotNull);
      expect(vs!.url, 'magnet:?xt=urn:btih:4b8a1c9e827163f45d8b2e1a90c1f3a2b4e5d6c7');
      expect(vs.container, SourceContainer.torrent);
      expect(vs.label, contains('[P2P Torrent]'));
    });
  });

  group('Stremio Client URL canonicalization', () {
    test('canonicalizes stremio:// scheme to https://', () {
      final canon = StremioClient.canonicalizeManifestUrl('stremio://torrentio.strem.fun/manifest.json');
      expect(canon, 'https://torrentio.strem.fun/manifest.json');
    });

    test('appends /manifest.json if omitted', () {
      final canon1 = StremioClient.canonicalizeManifestUrl('https://torrentio.strem.fun');
      final canon2 = StremioClient.canonicalizeManifestUrl('https://torrentio.strem.fun/');
      expect(canon1, 'https://torrentio.strem.fun/manifest.json');
      expect(canon2, 'https://torrentio.strem.fun/manifest.json');
    });

    test('extracts base URL correctly', () {
      final base = StremioClient.getBaseUrl('https://torrentio.strem.fun/manifest.json');
      expect(base, 'https://torrentio.strem.fun');
    });
  });

  group('Stremio Provider integration', () {
    test('formats sourceId and displayName', () {
      const manifest = StremioManifest(
        id: 'org.stremio.torrentio',
        name: 'Torrentio',
        version: '1.0.12',
      );
      final entry = StremioAddonEntry(
        manifestUrl: 'https://torrentio.strem.fun/manifest.json',
        manifest: manifest,
        installedAt: DateTime.now(),
      );
      final provider = StremioProvider(
        entry: entry,
        client: StremioClient(),
      );

      expect(provider.sourceId, 'stremio:org.stremio.torrentio');
      expect(provider.displayName, 'Torrentio');
      expect(provider.baseUrl, 'https://torrentio.strem.fun');
    });
  });
}
