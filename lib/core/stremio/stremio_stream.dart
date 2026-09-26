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

  static const _defaultTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://tracker.bittor.pw:1337/announce',
    'udp://public.popcorn-tracker.org:6969/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://explodie.org:6969/announce',
    'udp://tracker.coppersurfer.tk:6969/announce',
  ];

  static String _formatBytes(num bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  /// Builds a full magnet URI from [hash], appending trackers and display name.
  /// When an addon does not provide trackers in behaviorHints, top-tier public
  /// trackers are automatically appended so libtorrent resolves metadata in seconds
  /// rather than timing out with no_metadata.
  String _buildMagnet(String hash) {
    final buf = StringBuffer('magnet:?xt=urn:btih:$hash');

    // Display name (dn) — from title or name for peer visibility
    final dn = (title?.trim().isNotEmpty == true ? title! : name)?.trim();
    if (dn != null && dn.isNotEmpty) {
      buf.write('&dn=${Uri.encodeComponent(dn)}');
    }

    final addedTrackers = <String>{};

    // Trackers from behaviorHints.sources if present
    final sources = behaviorHints?['sources'];
    if (sources is List) {
      for (final s in sources) {
        final str = s?.toString() ?? '';
        if (str.startsWith('tracker:')) {
          final tracker = str.substring('tracker:'.length).trim();
          if (tracker.isNotEmpty && addedTrackers.add(tracker)) {
            buf.write('&tr=${Uri.encodeComponent(tracker)}');
          }
        }
      }
    }

    // Always include top tier-1 public trackers to prevent no_metadata timeout
    for (final tr in _defaultTrackers) {
      if (addedTrackers.add(tr)) {
        buf.write('&tr=${Uri.encodeComponent(tr)}');
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
    // 1. Clean addon / provider name (e.g. "Torrentio\n1080p" -> "Torrentio")
    final rawName = (name ?? '').replaceAll('\r', '').trim();
    final nameLines = rawName.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final addonBase = nameLines.isNotEmpty ? nameLines.first : addonName.split('\n').first.trim();

    // 2. Parse title text and extract metrics (seeders, leechers, size, group)
    final rawTitle = (title ?? description ?? '').replaceAll('\r', '').trim();
    final titleLines = rawTitle.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String? seeders;
    String? leechers;
    String? sizeStr;
    String? sourceGroup;
    final otherParts = <String>[];

    // Check behaviorHints for videoSize
    final videoSizeBytes = behaviorHints?['videoSize'];
    if (videoSizeBytes is num && videoSizeBytes > 0) {
      sizeStr = _formatBytes(videoSizeBytes);
    }

    final seederRegex = RegExp(r'(?:👤|🌱)\s*(\d+)|\b(\d+)\s*(?:seeders?|seeds?)\b', caseSensitive: false);
    final leecherRegex = RegExp(r'(?:👥|🧲)\s*(\d+)|\b(\d+)\s*(?:leechers?|leech?)\b', caseSensitive: false);
    final sizeRegex = RegExp(r'(?:💾|📦)?\s*(\d+(?:\.\d+)?\s*(?:GB|MB|GiB|MiB))\b', caseSensitive: false);
    final groupRegex = RegExp(r'⚙️\s*([A-Za-z0-9_.\-]+)');

    for (final line in titleLines) {
      // Check for seeders
      final sm = seederRegex.firstMatch(line);
      if (sm != null && seeders == null) {
        seeders = sm.group(1) ?? sm.group(2);
      }
      // Check for leechers
      final lm = leecherRegex.firstMatch(line);
      if (lm != null && leechers == null) {
        leechers = lm.group(1) ?? lm.group(2);
      }
      // Check for size if not already found from behaviorHints
      if (sizeStr == null) {
        final szm = sizeRegex.firstMatch(line);
        if (szm != null) {
          sizeStr = szm.group(1);
        }
      }
      // Check for source group
      final gm = groupRegex.firstMatch(line);
      if (gm != null && sourceGroup == null) {
        sourceGroup = gm.group(1);
      }

      // If line is not purely metrics, preserve it as clean title / filename
      final stripped = line
          .replaceAll(seederRegex, '')
          .replaceAll(leecherRegex, '')
          .replaceAll(sizeRegex, '')
          .replaceAll(groupRegex, '')
          .replaceAll(RegExp(r'[👤👥💾⚙️🌱🧲·\s]+'), ' ')
          .trim();
      if (stripped.isNotEmpty && !otherParts.contains(stripped)) {
        otherParts.add(stripped);
      }
    }

    final quality = _detectQuality();

    // 3. Assemble clean label with metrics prominently up front:
    // e.g. "Torrentio · 1080p · 💾 2.1 GB · 👤 250 (👥 12) · ⚙️ RARBG · [Torrent] · Movie.Name..."
    final parts = <String>[];
    parts.add(addonBase);

    if (quality != 'Auto') {
      parts.add(quality);
    }

    if (sizeStr != null && sizeStr.isNotEmpty) {
      parts.add('💾 $sizeStr');
    }

    if (seeders != null && seeders.isNotEmpty) {
      if (leechers != null && leechers.isNotEmpty) {
        parts.add('👤 $seeders (👥 $leechers)');
      } else {
        parts.add('👤 $seeders');
      }
    }

    if (sourceGroup != null && sourceGroup.isNotEmpty) {
      parts.add('⚙️ $sourceGroup');
    }

    if (isTorrent) {
      parts.add('[Torrent]');
    }

    for (final op in otherParts) {
      if (!parts.contains(op)) {
        parts.add(op);
      }
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
