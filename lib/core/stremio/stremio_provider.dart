import '../models/episode.dart';
import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../models/video_source.dart';
import '../provider/base_provider.dart';
import 'stremio_client.dart';
import 'stremio_manifest.dart';
import 'stremio_store.dart';

class StremioProvider implements BaseProvider {
  StremioProvider({
    required this.entry,
    required this.client,
  })  : baseUrl = StremioClient.getBaseUrl(entry.manifestUrl),
        manifest = entry.manifest;

  final StremioAddonEntry entry;
  final StremioManifest manifest;
  final StremioClient client;
  final String baseUrl;

  @override
  String get sourceId => 'stremio:${manifest.id}';

  @override
  String get displayName => manifest.name;

  @override
  Future<ProviderInfo> getInfo() async {
    return ProviderInfo(
      name: displayName,
      lang: 'en',
      baseUrl: baseUrl,
      logo: manifest.logo,
      type: ProviderType.movie,
      version: manifest.version,
    );
  }

  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) async {
    if (!manifest.supportsCatalogs || manifest.catalogs.isEmpty) {
      return null;
    }

    final sections = <HomeSection>[];
    for (final cat in manifest.catalogs.take(4)) {
      final metas = await client.getCatalog(
        baseUrl: baseUrl,
        type: cat.type,
        id: cat.id,
      );
      if (metas.isNotEmpty) {
        final items = metas.map((m) => _metaToMediaItem(m, cat.type)).toList();
        sections.add(
          HomeSection(
            title: cat.name ?? '${cat.type.toUpperCase()} - ${cat.id}',
            items: items,
          ),
        );
      }
    }
    return sections.isEmpty ? null : sections;
  }

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) async {
    if (!manifest.supportsCatalogs || manifest.catalogs.isEmpty) {
      return const [];
    }
    final primary = manifest.catalogs.first;
    final skip = (page - 1) * 20;
    final metas = await client.getCatalog(
      baseUrl: baseUrl,
      type: primary.type,
      id: primary.id,
      skip: skip,
    );
    return metas.map((m) => _metaToMediaItem(m, primary.type)).toList();
  }

  @override
  Future<List<MediaItem>> search(
    String query,
    int page, {
    String category = '',
  }) async {
    if (!manifest.supportsCatalogs) return const [];
    for (final cat in manifest.catalogs) {
      if (cat.extraSupported?.contains('search') == true ||
          cat.extraRequired?.contains('search') == true ||
          cat.id.contains('search')) {
        final metas = await client.getCatalog(
          baseUrl: baseUrl,
          type: cat.type,
          id: cat.id,
          searchQuery: query,
        );
        if (metas.isNotEmpty) {
          return metas.map((m) => _metaToMediaItem(m, cat.type)).toList();
        }
      }
    }
    return const [];
  }

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) async {
    final parsed = _parseEpisodeUrl(url);
    return MediaDetail(
      id: parsed.id,
      title: parsed.id,
      url: url,
      type: parsed.type == 'series' ? ProviderType.movie : ProviderType.movie,
      sourceId: sourceId,
      isSeries: parsed.type == 'series',
      episodes: [
        Episode(
          id: parsed.id,
          number: parsed.episode?.toDouble() ?? 1.0,
          title: parsed.id,
          url: url,
        ),
      ],
    );
  }

  @override
  Future<List<Episode>> getEpisodes(String url, {String category = 'sub'}) async {
    final parsed = _parseEpisodeUrl(url);
    return [
      Episode(
        id: parsed.id,
        number: parsed.episode?.toDouble() ?? 1.0,
        title: parsed.id,
        url: url,
      ),
    ];
  }

  @override
  Future<List<VideoSource>> getVideoSources(
    String episodeUrl, {
    bool fast = false,
  }) async {
    final target = _parseEpisodeUrl(episodeUrl);
    if (target.id.isEmpty) return const [];

    final streams = await client.getStreams(
      baseUrl: baseUrl,
      type: target.type,
      id: target.id,
    );

    final sources = <VideoSource>[];
    for (final s in streams) {
      final vs = s.toVideoSource(addonName: displayName);
      if (vs != null) {
        sources.add(vs);
      }
    }
    return sources;
  }

  MediaItem _metaToMediaItem(Map<String, dynamic> meta, String catalogType) {
    final id = (meta['id'] ?? '').toString();
    final name = (meta['name'] ?? meta['title'] ?? id).toString();
    final poster = meta['poster']?.toString();
    final isTv = catalogType == 'series' || meta['type'] == 'series';
    final imdbId = id.startsWith('tt') ? id : null;

    return MediaItem(
      id: id,
      title: name,
      cover: poster,
      url: 'stremio://${manifest.id}/stream/$catalogType/$id',
      type: ProviderType.movie,
      sourceId: sourceId,
      imdbId: imdbId,
      tmdbIsTv: isTv,
      year: meta['year']?.toString() ?? meta['releaseInfo']?.toString(),
    );
  }

  ({String type, String id, int? season, int? episode}) _parseEpisodeUrl(String url) {
    var u = url.trim();

    // Format: stremio://<addonId>/stream/{type}/{id}
    if (u.startsWith('stremio://')) {
      final uri = Uri.tryParse(u);
      if (uri != null && uri.pathSegments.length >= 3) {
        // segments: ['stream', 'movie', 'tt1234567']
        final type = uri.pathSegments[1];
        final id = uri.pathSegments.sublist(2).join('/');
        return _parseStremioId(type, id);
      }
    }

    if (u.startsWith('imdb:')) {
      u = u.substring('imdb:'.length);
    }

    // Check for "tt1234567:1:1"
    if (u.contains(':')) {
      final parts = u.split(':');
      if (parts.length >= 3) {
        final id = parts[0];
        final season = int.tryParse(parts[1]);
        final ep = int.tryParse(parts[2]);
        return (type: 'series', id: '$id:${season ?? 1}:${ep ?? 1}', season: season, episode: ep);
      }
    }

    // Default movie ID
    final isSeries = u.contains(':');
    return (type: isSeries ? 'series' : 'movie', id: u, season: null, episode: null);
  }

  ({String type, String id, int? season, int? episode}) _parseStremioId(
    String type,
    String id,
  ) {
    if (type == 'series' && id.contains(':')) {
      final parts = id.split(':');
      if (parts.length >= 3) {
        return (
          type: 'series',
          id: id,
          season: int.tryParse(parts[1]),
          episode: int.tryParse(parts[2]),
        );
      }
    }
    return (type: type, id: id, season: null, episode: null);
  }
}
