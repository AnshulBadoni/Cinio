import 'package:equatable/equatable.dart';

import '../models/video_source.dart';

class StremioSubtitle extends Equatable {
  final String id;
  final String url;
  final String lang;

  const StremioSubtitle({
    required this.id,
    required this.url,
    required this.lang,
  });

  factory StremioSubtitle.fromJson(Map<String, dynamic> json) {
    return StremioSubtitle(
      id: (json['id'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      lang: (json['lang'] ?? json['language'] ?? 'en').toString(),
    );
  }

  Subtitle toVideoSubtitle() {
    final cleanUrl = url.trim();
    String? format;
    if (cleanUrl.endsWith('.vtt')) {
      format = 'vtt';
    } else if (cleanUrl.endsWith('.srt')) {
      format = 'srt';
    }
    return Subtitle(
      url: cleanUrl,
      lang: lang,
      label: lang,
      format: format,
    );
  }

  @override
  List<Object?> get props => [id, url, lang];
}

class StremioStream extends Equatable {
  final String? url;
  final String? name;
  final String? title;
  final String? description;
  final String? infoHash;
  final int? fileIdx;
  final Map<String, dynamic>? behaviorHints;
  final List<StremioSubtitle> subtitles;

  const StremioStream({
    this.url,
    this.name,
    this.title,
    this.description,
    this.infoHash,
    this.fileIdx,
    this.behaviorHints,
    this.subtitles = const [],
  });

  factory StremioStream.fromJson(Map<String, dynamic> json) {
    final rawSubtitles = json['subtitles'] as List? ?? const [];
    final subs = rawSubtitles
        .whereType<Map<String, dynamic>>()
        .map((s) => StremioSubtitle.fromJson(s))
        .where((s) => s.url.isNotEmpty)
        .toList();

    return StremioStream(
      url: json['url']?.toString(),
      name: json['name']?.toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      infoHash: json['infoHash']?.toString(),
      fileIdx: json['fileIdx'] is int
          ? json['fileIdx'] as int
          : (int.tryParse(json['fileIdx']?.toString() ?? '')),
      behaviorHints: json['behaviorHints'] as Map<String, dynamic>?,
      subtitles: subs,
    );
  }

  Map<String, dynamic> toJson() => {
    if (url != null) 'url': url,
    if (name != null) 'name': name,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (infoHash != null) 'infoHash': infoHash,
    if (fileIdx != null) 'fileIdx': fileIdx,
    if (behaviorHints != null) 'behaviorHints': behaviorHints,
    if (subtitles.isNotEmpty)
      'subtitles': subtitles.map((s) => {'id': s.id, 'url': s.url, 'lang': s.lang}).toList(),
  };

  /// Translates Stremio stream to Cinio's VideoSource.
  VideoSource? toVideoSource({required String addonName}) {
    final streamUrl = url?.trim();
    if (streamUrl == null || streamUrl.isEmpty) {
      // In pure HTTP Cinio, raw torrents without direct URL are represented with magnet URL
      if (infoHash != null && infoHash!.isNotEmpty) {
        final magnet = _buildMagnet(infoHash!);
        return VideoSource(
          url: magnet,
          label: _buildLabel(addonName, isTorrent: true),
          quality: _detectQuality(),
          container: SourceContainer.torrent,
          headers: _extractHeaders(),
          subtitles: subtitles.map((s) => s.toVideoSubtitle()).toList(),
        );
      }
      return null;
    }

    final container = _detectContainer(streamUrl);
    final quality = _detectQuality();
    final label = _buildLabel(addonName);
    final headers = _extractHeaders();

    return VideoSource(
      url: streamUrl,
      label: label,
      quality: quality,
      container: container,
      headers: headers,
      subtitles: subtitles.map((s) => s.toVideoSubtitle()).toList(),
    );
  }

  /// Builds a full magnet URI from [hash], appending trackers and display name
  /// when available. Torrentio supplies trackers in behaviorHints['sources']
  /// as a List of "tracker:udp://..." strings — without them the torrent
  /// engine can't find peers and times out immediately.
  String _buildMagnet(String hash) {
    final buf = StringBuffer('magnet:?xt=urn:btih:$hash');

    // Display name (dn) — from title or name for peer visibility
    final dn = (title?.trim().isNotEmpty == true ? title! : name)?.trim();
    if (dn != null && dn.isNotEmpty) {
      buf.write('&dn=${Uri.encodeComponent(dn)}');
    }

    // Trackers (tr) — Torrentio sends them in behaviorHints.sources as
    // ["tracker:udp://opentracker.i2p.rocks:6969/announce", ...]
    final sources = behaviorHints?['sources'];
    if (sources is List) {
      for (final s in sources) {
        final str = s?.toString() ?? '';
        if (str.startsWith('tracker:')) {
          final tracker = str.substring('tracker:'.length);
          if (tracker.isNotEmpty) {
            buf.write('&tr=${Uri.encodeComponent(tracker)}');
          }
        }
      }
    }

    return buf.toString();
  }

  Map<String, String>? _extractHeaders() {
    if (behaviorHints == null) return null;
    final reqHeaders = behaviorHints!['proxyHeaders']?['request'] ??
        behaviorHints!['headers'] ??
        behaviorHints!['notWebReadyHeaders'];
    if (reqHeaders is Map) {
      return reqHeaders.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return null;
  }

  SourceContainer _detectContainer(String u) {
    final lower = u.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('/hls/')) {
      return SourceContainer.hls;
    }
    if (lower.contains('.mp4') || lower.contains('.mkv') || lower.contains('.webm')) {
      return SourceContainer.mp4;
    }
    return SourceContainer.unknown;
  }

  String _detectQuality() {
    final combined = '${name ?? ''} ${title ?? ''} ${description ?? ''}'.toLowerCase();
    if (combined.contains('4k') || combined.contains('2160p') || combined.contains('uhd')) {
      return '4K';
    }
    if (combined.contains('1080p') || combined.contains('fhd')) {
      return '1080p';
    }
    if (combined.contains('720p') || combined.contains('hd')) {
      return '720p';
    }
    if (combined.contains('480p') || combined.contains('sd')) {
      return '480p';
    }
    return 'Auto';
  }

  String _buildLabel(String addonName, {bool isTorrent = false}) {
    final parts = <String>[];
    if (name != null && name!.trim().isNotEmpty) {
      parts.add(name!.trim());
    } else {
      parts.add(addonName);
    }

    if (title != null && title!.trim().isNotEmpty) {
      // Split on newlines to clean up Torrentio multi-line formatting
      final cleanTitle = title!.replaceAll('\n', ' · ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleanTitle.isNotEmpty && !parts.contains(cleanTitle)) {
        parts.add(cleanTitle);
      }
    } else if (description != null && description!.trim().isNotEmpty) {
      final cleanDesc = description!.replaceAll('\n', ' · ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleanDesc.isNotEmpty) {
        parts.add(cleanDesc);
      }
    }

    if (isTorrent) {
      parts.add('[P2P Torrent]');
    }

    return parts.join(' · ');
  }

  @override
  List<Object?> get props => [
    url,
    name,
    title,
    description,
    infoHash,
    fileIdx,
    behaviorHints,
    subtitles,
  ];
}
