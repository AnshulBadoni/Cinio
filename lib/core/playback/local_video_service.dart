import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../di/injector.dart';
import '../hive/safe_box.dart';
import '../metadata/theporndb.dart';
import '../metadata/tmdb_discover_service.dart';
import '../prefs/catalog_source_prefs.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/video_source.dart';
import '../playback/resume_store.dart';
import '../../features/player/player_screen.dart';

/// Representation of a local video discovered on the device.
class LocalVideoItem {
  LocalVideoItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
    required this.cleanTitle,
    this.extractedYear,
    this.season,
    this.episode,
    this.matchedTitle,
    this.matchedPoster,
    this.matchedBackdrop,
    this.matchedRating,
    this.matchedYear,
    this.matchedOverview,
    this.isMatched = false,
    this.matchAttempted = false,
    this.mediaItem,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;
  final String cleanTitle;
  final String? extractedYear;
  final int? season;
  final int? episode;

  String? matchedTitle;
  String? matchedPoster;
  String? matchedBackdrop;
  double? matchedRating;
  String? matchedYear;
  String? matchedOverview;
  bool isMatched;
  bool matchAttempted;
  MediaItem? mediaItem;

  String get id => path;

  bool get isLikelySeries => season != null || episode != null;

  String get displayTitle =>
      (matchedTitle != null && matchedTitle!.isNotEmpty) ? matchedTitle! : cleanTitle;

  /// Looks for a sidecar image or poster file in the same directory as the video file.
  String? get localThumbnailPath {
    try {
      final file = File(path);
      final parent = file.parent;
      final baseName = file.uri.pathSegments.last;
      final dot = baseName.lastIndexOf('.');
      final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
      for (final ext in ['jpg', 'jpeg', 'png', 'webp']) {
        final f = File('${parent.path}${Platform.pathSeparator}$stem.$ext');
        if (f.existsSync()) return f.path;
      }
      for (final common in ['poster.jpg', 'cover.jpg', 'folder.jpg', 'default.jpg']) {
        final f = File('${parent.path}${Platform.pathSeparator}$common');
        if (f.existsSync()) return f.path;
      }
    } catch (_) {}
    return null;
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    return (dot >= 0 && dot < name.length - 1)
        ? name.substring(dot + 1).toUpperCase()
        : 'VIDEO';
  }

  String get formattedSize {
    if (sizeBytes <= 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (sizeBytes >= gb) {
      return '${(sizeBytes / gb).toStringAsFixed(1)} GB';
    }
    if (sizeBytes >= mb) {
      return '${(sizeBytes / mb).toStringAsFixed(0)} MB';
    }
    return '${(sizeBytes / kb).toStringAsFixed(0)} KB';
  }

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'sizeBytes': sizeBytes,
        'modified': modified.millisecondsSinceEpoch,
        'cleanTitle': cleanTitle,
        'extractedYear': extractedYear,
        'season': season,
        'episode': episode,
        'matchedTitle': matchedTitle,
        'matchedPoster': matchedPoster,
        'matchedBackdrop': matchedBackdrop,
        'matchedRating': matchedRating,
        'matchedYear': matchedYear,
        'matchedOverview': matchedOverview,
        'isMatched': isMatched,
        'matchAttempted': matchAttempted,
      };

  factory LocalVideoItem.fromMap(Map<dynamic, dynamic> map) {
    return LocalVideoItem(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      modified: DateTime.fromMillisecondsSinceEpoch(
        (map['modified'] as num?)?.toInt() ?? 0,
      ),
      cleanTitle: map['cleanTitle'] as String? ?? '',
      extractedYear: map['extractedYear'] as String?,
      season: (map['season'] as num?)?.toInt(),
      episode: (map['episode'] as num?)?.toInt(),
      matchedTitle: map['matchedTitle'] as String?,
      matchedPoster: map['matchedPoster'] as String?,
      matchedBackdrop: map['matchedBackdrop'] as String?,
      matchedRating: (map['matchedRating'] as num?)?.toDouble(),
      matchedYear: map['matchedYear'] as String?,
      matchedOverview: map['matchedOverview'] as String?,
      isMatched: map['isMatched'] == true,
      matchAttempted: map['matchAttempted'] == true,
    );
  }
}

/// Service that scans device storage for video files, extracts clean titles,
/// matches against TMDB or TPDB metadata, and enables seamless playback.
class LocalVideoService extends ChangeNotifier {
  static const String boxName = 'local_video_store';

  static final Set<String> supportedExtensions = {
    'mp4',
    'mkv',
    'webm',
    'avi',
    'mov',
    'm4v',
    'ts',
    'flv',
    '3gp',
    'wmv',
    'mpg',
    'mpeg',
  };

  final List<LocalVideoItem> _items = [];
  bool _scanning = false;
  String? _statusMessage;

  List<LocalVideoItem> get items => List.unmodifiable(_items);
  bool get scanning => _scanning;
  String? get statusMessage => _statusMessage;

  Box? get _box => Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await openBoxSafely(boxName);
    }
  }

  /// Load cached items from Hive on startup for immediate UI rendering.
  Future<void> loadCached() async {
    final box = _box;
    if (box == null) return;
    final cachedList = box.get('cached_items') as List?;
    if (cachedList != null) {
      _items.clear();
      for (final raw in cachedList) {
        if (raw is Map) {
          final item = LocalVideoItem.fromMap(raw);
          // verify file still exists and is not in an excluded folder
          if (!isPathExcluded(item.path) && File(item.path).existsSync()) {
            _items.add(item);
          }
        }
      }
      notifyListeners();

      // Automatically retry matching in background for any unmatched items
      if (_items.any((it) => !it.isMatched)) {
        unawaited(_matchPendingItems());
      }
    }
  }

  List<String> get customFolders {
    final box = _box;
    if (box == null) return const [];
    final raw = box.get('custom_folders') as List? ?? box.get('included_folders') as List?;
    return (raw?.cast<String>() ?? <String>[]).toList();
  }

  List<String> get includedFolders => customFolders;

  List<String> get excludedFolders {
    final box = _box;
    if (box == null) return const [];
    final raw = box.get('excluded_folders') as List?;
    return (raw?.cast<String>() ?? <String>[]).toList();
  }

  bool isPathExcluded(String targetPath, [List<String>? explicitExcluded]) {
    if (targetPath.isEmpty) return false;
    final normalizedTarget = targetPath.replaceAll('\\', '/').toLowerCase();
    final list = explicitExcluded ?? excludedFolders;
    for (final excluded in list) {
      if (excluded.trim().isEmpty) continue;
      final normalizedExcluded = excluded.trim().replaceAll('\\', '/').toLowerCase();
      if (normalizedTarget == normalizedExcluded ||
          normalizedTarget.startsWith(normalizedExcluded.endsWith('/')
              ? normalizedExcluded
              : '$normalizedExcluded/')) {
        return true;
      }
    }
    return false;
  }

  Future<void> addCustomFolder(String path) => addIncludedFolder(path);
  Future<void> removeCustomFolder(String path) => removeIncludedFolder(path);

  Future<void> addIncludedFolder(String path) async {
    final cleanPath = path.trim();
    if (cleanPath.isEmpty) return;
    final folders = includedFolders;
    final normalized = cleanPath.replaceAll('\\', '/').toLowerCase();
    if (!folders.any((f) => f.replaceAll('\\', '/').toLowerCase() == normalized)) {
      folders.add(cleanPath);
      await _box?.put('custom_folders', folders);
      await _box?.put('included_folders', folders);

      // If previously excluded, remove it from excluded
      final excluded = excludedFolders;
      if (excluded.any((f) => f.replaceAll('\\', '/').toLowerCase() == normalized)) {
        excluded.removeWhere((f) => f.replaceAll('\\', '/').toLowerCase() == normalized);
        await _box?.put('excluded_folders', excluded);
      }

      await scan(forceRescan: true);
    }
  }

  Future<void> removeIncludedFolder(String path) async {
    final cleanPath = path.trim();
    final folders = includedFolders;
    final normalized = cleanPath.replaceAll('\\', '/').toLowerCase();
    folders.removeWhere((f) => f.replaceAll('\\', '/').toLowerCase() == normalized);
    await _box?.put('custom_folders', folders);
    await _box?.put('included_folders', folders);
    notifyListeners();
    await scan(forceRescan: true);
  }

  Future<void> addExcludedFolder(String path) async {
    final cleanPath = path.trim();
    if (cleanPath.isEmpty) return;
    final folders = excludedFolders;
    final normalized = cleanPath.replaceAll('\\', '/').toLowerCase();
    if (!folders.any((f) => f.replaceAll('\\', '/').toLowerCase() == normalized)) {
      folders.add(cleanPath);
      await _box?.put('excluded_folders', folders);

      // If it was in included folders, remove it
      final included = includedFolders;
      if (included.any((f) => f.replaceAll('\\', '/').toLowerCase() == normalized)) {
        included.removeWhere((f) => f.replaceAll('\\', '/').toLowerCase() == normalized);
        await _box?.put('custom_folders', included);
        await _box?.put('included_folders', included);
      }

      // Immediately purge any items matching the excluded folder
      _items.removeWhere((item) => isPathExcluded(item.path));
      _persistCache();
      notifyListeners();

      await scan(forceRescan: true);
    }
  }

  Future<void> removeExcludedFolder(String path) async {
    final cleanPath = path.trim();
    final folders = excludedFolders;
    final normalized = cleanPath.replaceAll('\\', '/').toLowerCase();
    folders.removeWhere((f) => f.replaceAll('\\', '/').toLowerCase() == normalized);
    await _box?.put('excluded_folders', folders);
    notifyListeners();
    await scan(forceRescan: true);
  }

  /// Request permissions and scan storage paths.
  Future<void> scan({bool forceRescan = false}) async {
    if (_scanning) return;
    _scanning = true;
    _statusMessage = 'Scanning device storage…';
    notifyListeners();

    try {
      await _requestPermissions();

      final searchDirs = await _resolveSearchDirectories();
      final discoveredFiles = <File>[];
      final seenPaths = <String>{};

      for (final dir in searchDirs) {
        if (!dir.existsSync()) continue;
        await _scanDirectory(dir, discoveredFiles, seenPaths, maxDepth: 2);
      }

      // Reconcile discovered files
      final existingMap = {for (final item in _items) item.path: item};
      final updatedList = <LocalVideoItem>[];

      for (final file in discoveredFiles) {
        final path = file.path;
        if (isPathExcluded(path)) continue;
        if (existingMap.containsKey(path)) {
          updatedList.add(existingMap[path]!);
        } else {
          final name = file.uri.pathSegments.lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => 'video',
          );
          final parsed = cleanFilename(name);
          final stat = file.statSync();

          final item = LocalVideoItem(
            path: path,
            name: name,
            sizeBytes: stat.size,
            modified: stat.modified,
            cleanTitle: parsed.cleanTitle,
            extractedYear: parsed.year,
            season: parsed.season,
            episode: parsed.episode,
          );
          updatedList.add(item);
        }
      }

      // Sort by modified date descending (newest first)
      updatedList.sort((a, b) => b.modified.compareTo(a.modified));

      _items.clear();
      _items.addAll(updatedList);
      _persistCache();
      notifyListeners();

      // Background metadata matching for unmatched items
      unawaited(_matchPendingItems());
    } catch (e) {
      debugPrint('[LocalVideoService] Scan error: $e');
    } finally {
      _scanning = false;
      _statusMessage = null;
      notifyListeners();
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      try {
        if (await Permission.videos.isDenied) {
          await Permission.videos.request();
        }
        if (await Permission.storage.isDenied) {
          await Permission.storage.request();
        }
      } catch (_) {}
    }
  }

  Future<List<Directory>> _resolveSearchDirectories() async {
    final dirs = <Directory>[];

    // 1. User-added custom folders
    for (final path in customFolders) {
      dirs.add(Directory(path));
    }

    if (Platform.isAndroid) {
      // Standard Android media directories
      const commonPaths = [
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/DCIM/Camera',
        '/storage/emulated/0/Videos',
      ];
      for (final p in commonPaths) {
        dirs.add(Directory(p));
      }

      try {
        final extDirs = await getExternalStorageDirectories();
        if (extDirs != null) {
          for (final d in extDirs) {
            dirs.add(d);
          }
        }
      } catch (_) {}
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final userHome = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (userHome.isNotEmpty) {
        dirs.add(Directory('$userHome${Platform.pathSeparator}Videos'));
        dirs.add(Directory('$userHome${Platform.pathSeparator}Downloads'));
      }
    }

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) dirs.add(downloadsDir);
    } catch (_) {}

    // Filter out directories that are explicitly excluded
    dirs.removeWhere((d) => isPathExcluded(d.path));

    return dirs;
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<File> result,
    Set<String> seen, {
    int currentDepth = 0,
    int maxDepth = 2,
  }) async {
    if (currentDepth > maxDepth) return;
    if (isPathExcluded(dir.path)) return;
    try {
      final entries = dir.listSync(followLinks: false);
      for (final entry in entries) {
        final path = entry.path;
        if (isPathExcluded(path)) continue;
        final name = entry.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => '',
        );

        // Skip hidden files/directories and system folders
        if (name.startsWith('.') || name.startsWith('\$')) continue;

        if (entry is File) {
          final dot = name.lastIndexOf('.');
          if (dot >= 0) {
            final ext = name.substring(dot + 1).toLowerCase();
            if (supportedExtensions.contains(ext)) {
              if (seen.add(path)) {
                final stat = entry.statSync();
                // Filter out tiny audio/junk assets (< 2MB)
                if (stat.size >= 2 * 1024 * 1024) {
                  result.add(entry);
                }
              }
            }
          }
        } else if (entry is Directory) {
          await _scanDirectory(
            entry,
            result,
            seen,
            currentDepth: currentDepth + 1,
            maxDepth: maxDepth,
          );
        }
      }
    } catch (_) {
      // Ignore permission or access denied directories
    }
  }

  /// Parses file names to strip release tags, dots, brackets, and extract year/season/episode.
  static ({String cleanTitle, String? year, int? season, int? episode}) cleanFilename(
    String filename,
  ) {
    var raw = filename;
    final dot = raw.lastIndexOf('.');
    if (dot > 0) raw = raw.substring(0, dot);

    // Normalize separators to spaces first so word boundaries match consistently
    final spaced = raw.replaceAll(RegExp(r'[._\-]'), ' ');

    // Season and episode match: e.g. S01E02 or 1x02
    int? seasonNum;
    int? epNum;
    final sEpMatch = RegExp(r'\b[sS](\d{1,2})[eE](\d{1,2})\b').firstMatch(spaced) ??
        RegExp(r'\b(\d{1,2})x(\d{1,2})\b').firstMatch(spaced);
    if (sEpMatch != null) {
      seasonNum = int.tryParse(sEpMatch.group(1)!);
      epNum = int.tryParse(sEpMatch.group(2)!);
    }

    // Standalone episode match: e.g. E1, E01, EP1, EP01, Ep.1, Episode 1, Part 1
    Match? epOnlyMatch;
    if (epNum == null) {
      epOnlyMatch = RegExp(r'\b[eE][pP]?\.?\s*(\d{1,3})\b').firstMatch(spaced) ??
          RegExp(r'\bepisode\s*(\d{1,3})\b', caseSensitive: false).firstMatch(spaced) ??
          RegExp(r'\bpart\s*(\d{1,3})\b', caseSensitive: false).firstMatch(spaced);
      if (epOnlyMatch != null) {
        epNum = int.tryParse(epOnlyMatch.group(1)!);
        seasonNum ??= 1;
      }
    }

    // Standalone season match: e.g. Season 2, S2
    Match? seasonOnlyMatch;
    if (seasonNum == null || (seasonNum == 1 && sEpMatch == null)) {
      seasonOnlyMatch = RegExp(r'\b(?:season|s)\s*(\d{1,2})\b', caseSensitive: false).firstMatch(spaced);
      if (seasonOnlyMatch != null && seasonOnlyMatch != epOnlyMatch) {
        final parsedS = int.tryParse(seasonOnlyMatch.group(1)!);
        if (parsedS != null) seasonNum = parsedS;
      }
    }

    // Extract 4-digit release year: 19xx or 20xx
    String? year;
    final yearMatch = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(spaced);
    if (yearMatch != null) {
      year = yearMatch.group(1);
    }

    // Cut off release tags, season/episode tags, or year tags to isolate the title
    int cutoff = spaced.length;
    void considerCutoff(Match? m) {
      if (m != null && m.start > 0 && m.start < cutoff) {
        cutoff = m.start;
      }
    }

    considerCutoff(sEpMatch);
    considerCutoff(seasonOnlyMatch);
    considerCutoff(epOnlyMatch);
    considerCutoff(yearMatch);

    String titlePart = spaced.substring(0, cutoff);
    var clean = titlePart.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ');
    clean = clean.replaceAll(
      RegExp(
        r'\b(1080p|720p|2160p|4k|uhd|bluray|bdrip|web-?dl|webrip|dvdrip|hdtv|x264|x265|h264|h265|hevc|aac|ac3|dts|repack|yify|rarbg|eztv|galaxyrg|part\s*\d+|s\d+e\d+|\d+x\d+)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    if (year != null) {
      clean = clean.replaceAll(year, ' ');
    }
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (clean.isEmpty) {
      clean = spaced.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (clean.isEmpty) clean = filename;

    // Capitalize words nicely if input was plain lowercase or uppercase
    if (clean == clean.toLowerCase() || clean == clean.toUpperCase()) {
      clean = clean.split(' ').map((w) {
        if (w.isEmpty) return '';
        final lower = w.toLowerCase();
        if ({'of', 'the', 'and', 'in', 'on', 'at', 'to', 'for'}.contains(lower)) {
          return lower;
        }
        return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
      }).join(' ');
      if (clean.isNotEmpty) {
        clean = '${clean[0].toUpperCase()}${clean.substring(1)}';
      }
    }

    return (cleanTitle: clean, year: year, season: seasonNum, episode: epNum);
  }

  /// Runs background metadata matching against TMDB or TPDB.
  Future<void> _matchPendingItems() async {
    final pending = _items.where((it) => !it.isMatched).toList();
    if (pending.isEmpty) return;

    for (final item in pending) {
      await matchItem(item);
    }
  }

  /// Matches a single video item against metadata sources.
  Future<void> matchItem(LocalVideoItem item, {String? overrideQuery}) async {
    item.matchAttempted = true;
    final query = (overrideQuery != null && overrideQuery.trim().isNotEmpty)
        ? overrideQuery.trim()
        : item.cleanTitle;

    try {
      final isAdultPreferred = sl.isRegistered<CatalogSourcePrefs>() &&
          sl<CatalogSourcePrefs>().source == CatalogSource.thePornDb;

      MediaItem? bestMatch;

      // 1. If adult is preferred, check TPDB first
      if (isAdultPreferred && sl.isRegistered<ThePornDb>()) {
        final tpdbResults = await sl<ThePornDb>().search(query);
        bestMatch = _findConfidentMatch(query, tpdbResults, year: item.extractedYear);
      }

      // 2. TMDB search
      if (bestMatch == null && sl.isRegistered<TmdbDiscoverService>()) {
        final primaryType = item.isLikelySeries ? 'series' : 'movies';
        final secondaryType = item.isLikelySeries ? 'movies' : 'series';

        var tmdbResults = await sl<TmdbDiscoverService>().search(
          query: query,
          type: primaryType,
        );
        bestMatch = _findConfidentMatch(query, tmdbResults, year: item.extractedYear);

        // Fallback to secondary type (e.g. miniseries catalogued as movie or vice versa)
        if (bestMatch == null) {
          tmdbResults = await sl<TmdbDiscoverService>().search(
            query: query,
            type: secondaryType,
          );
          bestMatch = _findConfidentMatch(query, tmdbResults, year: item.extractedYear);
        }

        // Fallback to type 'all'
        if (bestMatch == null) {
          tmdbResults = await sl<TmdbDiscoverService>().search(
            query: query,
            type: 'all',
          );
          bestMatch = _findConfidentMatch(query, tmdbResults, year: item.extractedYear);
        }
      }

      // 3. Fallback to TPDB if not adult preferred
      if (bestMatch == null && !isAdultPreferred && sl.isRegistered<ThePornDb>()) {
        final tpdbResults = await sl<ThePornDb>().search(query);
        bestMatch = _findConfidentMatch(query, tpdbResults, year: item.extractedYear);
      }

      if (bestMatch != null) {
        item.isMatched = true;
        item.matchedTitle = item.isLikelySeries && item.episode != null
            ? '${bestMatch.title} S${item.season ?? 1}:E${item.episode}'
            : bestMatch.title;
        item.matchedPoster = bestMatch.cover;
        item.matchedBackdrop = bestMatch.heroImage ?? bestMatch.cover;
        item.matchedRating = bestMatch.rating;
        item.matchedYear = bestMatch.year;
        item.mediaItem = bestMatch;
        _persistCache();
        notifyListeners();
      }
    } catch (_) {
      // Matching failed gracefully, item displays fallback poster
    }
  }

  /// Checks candidate list and only returns a candidate if it passes a strict confidence threshold.
  /// Prevents false or wrong matches.
  static MediaItem? _findConfidentMatch(
    String query,
    List<MediaItem> candidates, {
    String? year,
  }) {
    if (candidates.isEmpty) return null;

    final normQuery = _normalizeForComparison(query);
    if (normQuery.isEmpty) return null;

    final queryWords = normQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    MediaItem? best;
    double bestScore = 0.0;

    for (final candidate in candidates) {
      final candTitle = candidate.title;
      final candEng = candidate.englishTitle ?? '';
      final normCand = _normalizeForComparison(candTitle);
      final normEng = _normalizeForComparison(candEng);

      final scoreTitle = _computeMatchScore(normQuery, queryWords, normCand);
      final scoreEng = normEng.isNotEmpty
          ? _computeMatchScore(normQuery, queryWords, normEng)
          : 0.0;
      var score = scoreTitle > scoreEng ? scoreTitle : scoreEng;

      // Year bonus or penalty
      if (year != null && candidate.year != null && candidate.year!.isNotEmpty) {
        final y1 = int.tryParse(year);
        final y2 = int.tryParse(candidate.year!);
        if (y1 != null && y2 != null) {
          final diff = (y1 - y2).abs();
          if (diff == 0) {
            score += 0.15;
          } else if (diff <= 1) {
            score += 0.05;
          } else if (diff > 3) {
            score -= 0.30; // Significant penalty for mismatched release years
          }
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    // Require >= 60% confidence to accept the match; otherwise don't force a wrong match.
    if (bestScore >= 0.60) {
      return best;
    }
    return null;
  }

  static String _normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _computeMatchScore(
    String normQuery,
    Set<String> queryWords,
    String normTarget,
  ) {
    if (normTarget.isEmpty) return 0.0;
    if (normQuery == normTarget) return 1.0;

    // Substring match
    if (normTarget.startsWith(normQuery) || normQuery.startsWith(normTarget)) {
      final ratio = normQuery.length < normTarget.length
          ? normQuery.length / normTarget.length
          : normTarget.length / normQuery.length;
      if (ratio >= 0.6) return 0.85 * ratio;
    }

    // Word intersection / Jaccard similarity
    final targetWords = normTarget.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    if (targetWords.isEmpty) return 0.0;

    final intersection = queryWords.intersection(targetWords).length;
    final union = queryWords.union(targetWords).length;
    final jaccard = union > 0 ? intersection / union : 0.0;
    final queryCoverage = queryWords.isNotEmpty ? intersection / queryWords.length : 0.0;

    return (jaccard * 0.4) + (queryCoverage * 0.6);
  }

  void _persistCache() {
    final box = _box;
    if (box == null) return;
    final serialized = _items.map((it) => it.toMap()).toList();
    box.put('cached_items', serialized);
  }

  /// Launches local playback using the app's player.
  void playVideo(BuildContext context, LocalVideoItem item) {
    final effectiveTitle = item.displayTitle;
    final ep = Episode(
      id: item.path,
      title: effectiveTitle,
      url: item.path,
      thumbnail: item.matchedPoster,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          sourceId: 'local:file',
          episodes: [ep],
          startIndex: 0,
          resume: sl<ResumeStore>(),
          resolveSources: (_) async => [
            VideoSource(
              url: item.path,
              container: SourceContainer.mp4,
              quality: item.extension,
              label: item.name,
            ),
          ],
          showTitle: effectiveTitle,
          cover: item.matchedPoster,
        ),
      ),
    );
  }

  /// Deletes a local video file from disk and updates state.
  Future<bool> deleteVideo(LocalVideoItem item) async {
    try {
      final f = File(item.path);
      if (f.existsSync()) {
        await f.delete();
      }
      _items.removeWhere((it) => it.path == item.path);
      _persistCache();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[LocalVideoService] Delete error: $e');
      return false;
    }
  }
}
