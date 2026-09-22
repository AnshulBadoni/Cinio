import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logging/app_logger.dart';
import '../models/episode.dart';
import '../models/video_source.dart';
import '../platform/apple_tv.dart';
import '../repository/source_repository.dart';
import '../torrent/torrent_download_service.dart';
import '../torrent/torrent_prefs.dart';
import 'download_prefs.dart';
import 'download_record.dart';
import 'download_service.dart';
import 'package:watch_app/core/hive/safe_box.dart';

/// Controls which subtitle tracks are fetched alongside a download.
enum SubtitleDownloadMode { none, defaultOnly, all }

/// Owns offline downloads. Direct-file (MP4/MKV) sources go through
/// background_downloader (true background); HLS (m3u8) sources go through the
/// in-app [HlsDownloader] (segment fetch + decrypt + concat, foreground). Both
/// finish in the public Downloads folder. Records persist in the Hive
/// `downloads` box so the library survives restarts. A [ChangeNotifier] so the
/// UI can rebuild live. See docs/downloads-feature.md.
class DownloadManager extends ChangeNotifier {
  DownloadManager(
    this._repo, [
    DownloadPrefs? downloadPrefs,
    TorrentDownloadService? torrentSvc,
  ]) : _downloadPrefs = downloadPrefs ?? DownloadPrefs(),
       _torrentSvc = torrentSvc ?? TorrentDownloadService();

  final SourceRepository _repo;
  final DownloadPrefs _downloadPrefs;
  final TorrentDownloadService _torrentSvc;

  final Map<String, TorrentDownloadProgress> torrentProgress = {};

  static const String boxName = 'downloads';
  static const String _sharedDir = 'Zangetsu';
  static const int _resolveConcurrency = 3;

  /// Minimum interval between [notifyListeners] calls for progress updates.
  /// Status changes (done/failed/paused) bypass this and notify immediately.
  static const int _notifyThrottleMs = 120;

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await openBoxSafely<Map>(boxName);
    }
  }

  Box<Map> get _box => Hive.box<Map>(boxName);
  FileDownloader? _dl;
  FileDownloader get _fileDownloader => _dl ??= FileDownloader();

  final MemoryTaskQueue _mp4Queue = MemoryTaskQueue();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  final Map<String, DownloadRecord> _records = {};

  // ── In-memory-only maps (not persisted — lost on restart) ─────────────────

  /// Live DownloadTask objects for in-session control.
  ///
  /// **Restart behaviour:** After an app kill, these are gone. The [resume]
  /// path handles this by re-resolving the source (extractor URLs expire
  /// within minutes, so the old URL is almost certainly dead) and enqueuing a
  /// fresh task. background_downloader's `allowPause: true` + `retries: 5`
  /// means the *file* on disk is reused via HTTP Range if the server supports
  /// it — so progress is NOT lost even though the task object is new.
  ///
  /// **Must-test scenarios before shipping:**
  ///  1. Download 40% → kill → reopen → Resume → verify file continues, not restarts
  ///  2. Download 40% → kill → reopen → verify background_downloader auto-resumes
  ///  3. Download 40% → kill → reopen → source URL expired → verify re-resolve works
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, List<VideoSource>> _candidates = {};

  /// Per-download subtitle mode so fallback mirrors preserve the user's choice.
  final Map<String, SubtitleDownloadMode> _subtitleModes = {};

  /// Per-download Dio [CancelToken] so cancelling a video also aborts its
  /// in-flight subtitle HTTP requests instead of letting them silently finish.
  final Map<String, CancelToken> _subtitleCancels = {};

  /// Per-download timestamp of the last [notifyListeners] for progress events.
  /// Status transitions (done/failed/paused/queued) bypass the throttle.
  final Map<String, int> _lastNotifyMs = {};

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  bool _initialized = false;
  StreamSubscription<TaskUpdate>? _bgSub;
  StreamSubscription<Task>? _enqueueErrorSub;
  StreamSubscription<dynamic>? _hlsProgressSub;
  StreamSubscription<dynamic>? _hlsDoneSub;
  StreamSubscription<dynamic>? _hlsFailedSub;
  StreamSubscription<TorrentDownloadProgress>? _torrentSub;

  /// Wire notifications + update streams. Idempotent — safe to call more than once.
  void setup() {
    if (_initialized) return;
    _initialized = true;

    for (final raw in _box.values) {
      final r = DownloadRecord.fromMap(raw);
      _records[r.id] = r;
    }

    if (isAppleTv) {
      _listenTorrentDownloads();
      return;
    }

    final dl = _fileDownloader;
    dl.configureNotification(
      running: const TaskNotification('Downloading', '{filename}'),
      complete: const TaskNotification('Downloaded', '{filename}'),
      error: const TaskNotification('Download failed', '{filename}'),
      progressBar: true,
    );

    _bgSub = dl.updates.listen(_onUpdate);
    _mp4Queue.maxConcurrent = _downloadPrefs.parallelDownloads;
    dl.addTaskQueue(_mp4Queue);

    _enqueueErrorSub = _mp4Queue.enqueueErrors.listen((task) async {
      final rec = _records[task.taskId];
      if (rec == null || rec.status == DownloadStatus.canceled) return;
      AppLogger.instance.log(
        "[download] MP4 couldn't enqueue — ${rec.showTitle} · "
        '${rec.episodeTitle} [${rec.quality}]',
        level: 'E',
      );
      if (await _tryNext(rec)) return;
      _put(
        rec.copyWith(
          status: DownloadStatus.failed,
          error: () => "Couldn't start download",
        ),
      );
      _notifyImmediate(rec.id);
    });

    _listenBackgroundService();
    _listenTorrentDownloads();
    _reconcileServiceResults();
  }

  void setParallel(int n) {
    final v = n.clamp(DownloadPrefs.parallelMin, DownloadPrefs.parallelMax);
    _mp4Queue.maxConcurrent = v;
    _mp4Queue.advanceQueue();
    if (!isAppleTv) {
      try {
        DownloadService.instance.invoke('setParallel', {'n': v});
      } catch (_) {}
    }
  }

  void _listenBackgroundService() {
    if (isAppleTv) return;
    try {
      final svc = DownloadService.instance;
      _hlsProgressSub = svc.on('progress').listen((d) {
        final id = d?['id'] as String?;
        if (id == null) return;
        final rec = _records[id];
        if (rec == null || rec.status == DownloadStatus.canceled) return;
        final p = (d?['progress'] as num?)?.toDouble() ?? rec.progress;
        _put(rec.copyWith(status: DownloadStatus.downloading, progress: p));
        _notifyThrottled(id);
      });
      _hlsDoneSub = svc.on('done').listen((d) async {
        final id = d?['id'] as String?;
        if (id == null) return;
        final rec = _records[id];
        if (rec == null) return;
        _candidates.remove(id);
        var path = d?['filePath'] as String?;
        if (path != null && d?['needsFinalize'] == true) {
          final finalized = await _finalizeHls(
            path,
            customUri: d?['customUri'] as String?,
            subDir: d?['sharedSubDir'] as String?,
          );
          if (finalized != null) path = finalized;
        }
        await _markDone(rec, path);
        _notifyImmediate(id);
      });
      _hlsFailedSub = svc.on('failed').listen((d) async {
        final id = d?['id'] as String?;
        if (id == null) return;
        final rec = _records[id];
        if (rec == null || d?['canceled'] == true) return;
        final err = d?['error'] as String? ?? 'Download failed';
        AppLogger.instance.log(
          '[download] HLS failed — ${rec.showTitle} · ${rec.episodeTitle} '
          '[${rec.quality}]: $err',
          level: 'E',
        );
        if (await _tryNext(rec)) return;
        _put(rec.copyWith(status: DownloadStatus.failed, error: () => err));
        _notifyImmediate(id);
      });
    } catch (_) {}
  }

  void _listenTorrentDownloads() {
    if (isAppleTv) return;
    _torrentSub = _torrentSvc.events().listen((p) async {
      final rec = _records[p.id];
      if (rec == null || rec.status == DownloadStatus.canceled) return;
      torrentProgress[p.id] = p;
      final isTerminal = p.status == 'done' || p.status == 'failed';
      switch (p.status) {
        case 'done':
          _candidates.remove(p.id);
          await _markDone(rec, p.filePath);
        case 'failed':
          _put(
            rec.copyWith(
              status: DownloadStatus.failed,
              error: () => p.error ?? 'Torrent download failed',
            ),
          );
        case 'paused':
          _put(rec.copyWith(status: DownloadStatus.paused));
        default:
          _put(
            rec.copyWith(
              status: DownloadStatus.downloading,
              progress: p.progress,
            ),
          );
      }
      if (isTerminal) {
        _notifyImmediate(p.id);
      } else {
        _notifyThrottled(p.id);
      }
    });
  }

  Future<void> _reconcileServiceResults() async {
    try {
      final dir = await DownloadService.resultsDir();
      if (!await dir.exists()) return;
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final m = jsonDecode(await entity.readAsString()) as Map;
          final id = m['id'] as String?;
          final rec = id == null ? null : _records[id];
          if (rec != null && rec.status != DownloadStatus.done) {
            final status = m['status'] as String?;
            if (status == 'done') {
              _candidates.remove(id);
              var path = m['filePath'] as String?;
              if (path != null && m['needsFinalize'] == true) {
                final finalized = await _finalizeHls(
                  path,
                  customUri: m['customUri'] as String?,
                  subDir: m['sharedSubDir'] as String?,
                );
                if (finalized != null) path = finalized;
              }
              await _markDone(rec, path);
            } else if (status == 'failed') {
              final err = m['error'] as String? ?? 'Download failed';
              AppLogger.instance.log(
                '[download] HLS failed (finished offline) — '
                '${rec.showTitle} · ${rec.episodeTitle}: $err',
                level: 'E',
              );
              _put(
                rec.copyWith(status: DownloadStatus.failed, error: () => err),
              );
            }
          }
        } catch (e) {
          AppLogger.instance.log(
            '[download] reconcile parse error: $e',
            level: 'W',
          );
        }
        try {
          await entity.delete();
        } catch (_) {}
      }
      notifyListeners();
    } catch (e) {
      AppLogger.instance.log('[download] reconcile failed: $e', level: 'E');
    }
  }

  @override
  void dispose() {
    _bgSub?.cancel();
    _enqueueErrorSub?.cancel();
    _hlsProgressSub?.cancel();
    _hlsDoneSub?.cancel();
    _hlsFailedSub?.cancel();
    _torrentSub?.cancel();
    // Abort any in-flight subtitle fetches.
    for (final token in _subtitleCancels.values) {
      token.cancel('manager disposed');
    }
    _subtitleCancels.clear();
    _initialized = false;
    super.dispose();
  }

  // ── Notify helpers ────────────────────────────────────────────────────────

  /// Notify immediately — used for status transitions (done/failed/paused).
  void _notifyImmediate(String id) {
    _lastNotifyMs[id] = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Notify at most once per [_notifyThrottleMs] — used for progress ticks.
  /// Prevents 20 downloads × 60fps progress events from saturating the UI.
  void _notifyThrottled(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastNotifyMs[id] ?? 0;
    if (now - last < _notifyThrottleMs) return;
    _lastNotifyMs[id] = now;
    notifyListeners();
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  List<DownloadRecord> get all =>
      _records.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Map<String, List<DownloadRecord>> get byShow {
    final out = <String, List<DownloadRecord>>{};
    for (final r in all) {
      (out[r.showId] ??= []).add(r);
    }
    return out;
  }

  DownloadRecord? recordFor(String sourceId, String showId, String episodeId) =>
      _records[_idFor(sourceId, showId, episodeId)];

  // ── Enqueue ───────────────────────────────────────────────────────────────

  Future<void> enqueueEpisodes({
    required String sourceId,
    required String showId,
    required String showTitle,
    String? cover,
    Map<String, String>? coverHeaders,
    required String showUrl,
    required String category,
    required String quality,
    required List<Episode> episodes,
    required int nowMs,
    int? malId,
    SubtitleDownloadMode subtitleMode = SubtitleDownloadMode.defaultOnly,
  }) async {
    try {
      await Permission.notification.request();
    } catch (_) {}

    final pending = <DownloadRecord>[];
    for (final ep in episodes) {
      final id = _idFor(sourceId, showId, ep.id);
      final existing = _records[id];
      if (existing != null &&
          (existing.status == DownloadStatus.done || existing.isActive)) {
        continue;
      }
      final rec = DownloadRecord(
        id: id,
        sourceId: sourceId,
        showId: showId,
        showTitle: showTitle,
        cover: cover,
        coverHeaders: coverHeaders,
        showUrl: showUrl,
        episodeId: ep.id,
        episodeUrl: ep.url,
        episodeNumber: ep.number,
        episodeTitle: ep.title,
        category: category,
        quality: quality,
        malId: malId,
        createdAt: nowMs,
      );
      _put(rec);
      _subtitleModes[id] = subtitleMode;
      pending.add(rec);
    }
    notifyListeners();

    for (var i = 0; i < pending.length; i += _resolveConcurrency) {
      final batch = pending.sublist(
        i,
        (i + _resolveConcurrency).clamp(0, pending.length),
      );
      await Future.wait(batch.map((rec) => _resolveAndEnqueue(rec)));
    }
  }

  Future<void> enqueueSource({
    required String sourceId,
    required String showId,
    required String showTitle,
    String? cover,
    Map<String, String>? coverHeaders,
    required String showUrl,
    required String category,
    required Episode episode,
    required VideoSource source,
    required String qualityLabel,
    required int nowMs,
    int? malId,
    List<VideoSource> fallbacks = const [],
    SubtitleDownloadMode subtitleMode = SubtitleDownloadMode.defaultOnly,
  }) async {
    try {
      await Permission.notification.request();
    } catch (_) {}

    final replacing = _records[_idFor(sourceId, showId, episode.id)];
    final outgoing = (replacing?.filePath?.isNotEmpty ?? false)
        ? replacing!.filePath
        : replacing?.supersededPath;
    final rec = DownloadRecord(
      id: _idFor(sourceId, showId, episode.id),
      sourceId: sourceId,
      showId: showId,
      showTitle: showTitle,
      cover: cover,
      coverHeaders: coverHeaders,
      showUrl: showUrl,
      episodeId: episode.id,
      episodeUrl: episode.url,
      episodeNumber: episode.number,
      episodeTitle: episode.title,
      category: category,
      quality: qualityLabel,
      malId: malId,
      supersededPath: outgoing,
      createdAt: nowMs,
    );
    _put(rec);
    _subtitleModes[rec.id] = subtitleMode;
    notifyListeners();

    _candidates[rec.id] = [
      source,
      ...fallbacks.where((s) => s.url != source.url),
    ];
    await _enqueueTaskFor(rec, source);
  }

  Future<void> _resolveAndEnqueue(DownloadRecord rec) async {
    _put(rec.copyWith(status: DownloadStatus.resolving));
    notifyListeners();
    try {
      final sources = await _repo.sources(
        rec.episodeUrl,
        sourceId: rec.sourceId,
      );
      if (_isCanceled(rec.id)) return;
      final ranked = _ranked(sources, rec.quality);
      if (ranked.isEmpty) {
        AppLogger.instance.log(
          '[download] no downloadable source — ${rec.showTitle} · '
          '${rec.episodeTitle} (${sources.length} source(s))',
          level: 'E',
        );
        _put(
          rec.copyWith(
            status: DownloadStatus.unsupported,
            error: () => 'No downloadable (non-HLS) source',
          ),
        );
        notifyListeners();
        return;
      }
      _candidates[rec.id] = ranked;
      await _enqueueTaskFor(rec, ranked.first);
    } catch (e) {
      AppLogger.instance.log(
        'download resolve failed (${rec.showTitle}): $e',
        level: 'E',
      );
      _put(
        rec.copyWith(
          status: DownloadStatus.failed,
          error: () => 'Resolve failed',
        ),
      );
      notifyListeners();
    }
  }

  /// Advance to the next fallback mirror, preserving the original subtitle mode.
  Future<bool> _tryNext(DownloadRecord rec) async {
    final cands = _candidates[rec.id];
    if (cands == null || cands.length <= 1) return false;
    cands.removeAt(0);
    if (cands.isEmpty) return false;
    _put(rec.copyWith(status: DownloadStatus.resolving, progress: 0));
    notifyListeners();
    await _enqueueTaskFor(rec, cands.first);
    return true;
  }

  Future<void> _enqueueTaskFor(DownloadRecord rec, VideoSource source) async {
    if (_isCanceled(rec.id)) return;

    // Subtitle mode travels with the download — fallback mirrors inherit it.
    final subMode = _subtitleModes[rec.id] ?? SubtitleDownloadMode.defaultOnly;
    unawaited(_fetchSubtitles(rec, source, mode: subMode));

    if (_isHls(source)) {
      await _startHlsDownload(rec, source);
      return;
    }
    if (isTorrentSource(source)) {
      await _startTorrentDownload(rec, source);
      return;
    }

    final filename =
        '${_safe(rec.showTitle)}_E${rec.episodeNumber?.toInt() ?? ''}'
        '_${_safe(rec.quality)}${_ext(source.url)}';
    final displayName =
        '${rec.showTitle} · E${rec.episodeNumber?.toInt() ?? ''}';
    final headers = source.headers ?? const <String, String>{};

    final loc = _downloadPrefs.locationUri;
    final safUri = loc != null && loc.isNotEmpty && isUriPath(loc) ? loc : null;
    final DownloadTask task = safUri != null
        ? UriDownloadTask(
            taskId: rec.id,
            url: source.url,
            filename: filename,
            headers: headers,
            directoryUri: Uri.parse(safUri),
            updates: Updates.statusAndProgress,
            retries: 5,
            allowPause: true,
            displayName: displayName,
          )
        : DownloadTask(
            taskId: rec.id,
            url: source.url,
            filename: filename,
            headers: headers,
            directory: '$_sharedDir/${_safe(rec.showTitle)}',
            baseDirectory: BaseDirectory.applicationDocuments,
            updates: Updates.statusAndProgress,
            retries: 5,
            allowPause: true,
            displayName: displayName,
          );
    _tasks[rec.id] = task;
    _put(rec.copyWith(status: DownloadStatus.queued, progress: 0));
    _notifyImmediate(rec.id);
    _mp4Queue.add(task);
  }

  Future<void> _startHlsDownload(DownloadRecord rec, VideoSource source) async {
    _put(rec.copyWith(status: DownloadStatus.downloading, progress: 0));
    _notifyImmediate(rec.id);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final safeShow = _safe(rec.showTitle);
      final dir = Directory('${docs.path}/$_sharedDir/$safeShow');
      await dir.create(recursive: true);
      final outputPath =
          '${dir.path}/${safeShow}_E${rec.episodeNumber?.toInt() ?? ''}'
          '_${_safe(rec.quality)}.ts';

      if (isAppleTv) {
        throw UnsupportedError(
          'Background HLS downloads are not available on Apple TV',
        );
      }

      if (!await DownloadService.instance.isRunning()) {
        await DownloadService.instance.startService();
      }
      DownloadService.instance.invoke('download', {
        'id': rec.id,
        'url': source.url,
        'headers': source.headers ?? const <String, String>{},
        'outputPath': outputPath,
        'quality': rec.quality,
        'label': 'E${rec.episodeNumber?.toInt() ?? ''}',
        'showTitle': rec.showTitle,
        'sharedSubDir': '$_sharedDir/$safeShow',
        'customUri': _downloadPrefs.locationUri,
        'parallel': _downloadPrefs.parallelDownloads,
        'connections': _downloadPrefs.connectionsPerDownload,
      });
    } catch (_) {
      if (_isCanceled(rec.id)) return;
      if (await _tryNext(rec)) return;
      _put(
        rec.copyWith(
          status: DownloadStatus.failed,
          error: () => "Couldn't start download",
        ),
      );
      _notifyImmediate(rec.id);
    }
  }

  // ── Native channels ───────────────────────────────────────────────────────

  static const MethodChannel _downloadChannel = MethodChannel(
    'zangetsu/download',
  );

  Future<bool> _remuxToMp4(String input, String output) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _downloadChannel.invokeMethod<bool>('remuxTsToMp4', {
        'input': input,
        'output': output,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<({String path, String label, bool removable})>>
  listDownloadVolumes() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _downloadChannel.invokeMethod<List<dynamic>>(
        'listDownloadVolumes',
      );
      if (raw == null) return const [];
      return raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return (
          path: m['path'] as String,
          label: (m['label'] as String?) ?? 'Storage',
          removable: (m['removable'] as bool?) ?? false,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Finalize / move ───────────────────────────────────────────────────────

  Future<String?> _finalizeHls(
    String tsPath, {
    String? customUri,
    String? subDir,
  }) async {
    final dir = subDir ?? _sharedDir;
    final isVolume =
        customUri != null && customUri.isNotEmpty && !isUriPath(customUri);

    if (isVolume && Platform.isAndroid) {
      try {
        final destDir = Directory('$customUri/$dir');
        await destDir.create(recursive: true);
        final mp4 =
            '${destDir.path}/${_withExt(tsPath.split('/').last, 'mp4')}';
        if (await _remuxToMp4(tsPath, mp4)) {
          try {
            await File(tsPath).delete();
          } catch (_) {}
          return mp4;
        }
        return await _moveToVolume(tsPath, customUri, dir) ?? tsPath;
      } catch (_) {
        return tsPath;
      }
    }
    if (isVolume) {
      return await _moveToVolume(tsPath, customUri, dir) ?? tsPath;
    }

    var publish = tsPath;
    if (Platform.isAndroid) {
      final mp4 = _withExt(tsPath, 'mp4');
      final remuxed = mp4 != tsPath && await _remuxToMp4(tsPath, mp4);
      debugPrint(
        '[dl] HLS finalize: ${remuxed ? 'remuxed to mp4' : 'kept .ts'}',
      );
      if (remuxed) {
        publish = mp4;
        try {
          await File(tsPath).delete();
        } catch (_) {}
      }
    }
    if (customUri != null && customUri.isNotEmpty) {
      final moved = await _moveIntoTree(
        publish,
        customUri,
        publish.split('/').last,
      );
      return moved ?? publish;
    }
    try {
      final moved = await _fileDownloader.moveFileToSharedStorage(
        publish,
        SharedStorage.downloads,
        directory: dir,
      );
      return moved ?? publish;
    } catch (_) {
      return publish;
    }
  }

  Future<String?> _moveToVolume(
    String localPath,
    String volumeBase,
    String subDir,
  ) async {
    try {
      final dir = Directory('$volumeBase/$subDir');
      await dir.create(recursive: true);
      final dest = '${dir.path}/${localPath.split('/').last}';
      await File(localPath).copy(dest);
      try {
        await File(localPath).delete();
      } catch (_) {}
      return dest;
    } catch (_) {
      return null;
    }
  }

  String _withExt(String path, String ext) {
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    final base = dot > slash ? path.substring(0, dot) : path;
    return '$base.$ext';
  }

  // ── Subtitle fetching ─────────────────────────────────────────────────────

  /// Download subtitle sidecar files. Uses a [CancelToken] so the HTTP request
  /// is aborted if the parent download is cancelled mid-fetch. Streams to disk
  /// in chunks to avoid buffering unexpectedly large responses in memory.
  Future<void> _fetchSubtitles(
    DownloadRecord rec,
    VideoSource source, {
    SubtitleDownloadMode mode = SubtitleDownloadMode.defaultOnly,
  }) async {
    if (mode == SubtitleDownloadMode.none) return;
    if (source.subtitles.isEmpty) return;
    final live = _records[rec.id];
    if (live == null || live.status == DownloadStatus.canceled) return;
    if (live.subtitles.isNotEmpty) return;

    final tracks = mode == SubtitleDownloadMode.all
        ? source.subtitles
        : _defaultSubtitleOnly(source.subtitles);
    if (tracks.isEmpty) return;

    // Create a cancel token tied to this download's lifecycle.
    final cancelToken = CancelToken();
    _subtitleCancels[rec.id] = cancelToken;

    try {
      final docs = await getApplicationDocumentsDirectory();
      final safeShow = _safe(rec.showTitle);
      final dir = Directory('${docs.path}/$_sharedDir/$safeShow/subs');
      await dir.create(recursive: true);
      final epTag = 'E${rec.episodeNumber?.toInt() ?? ''}';
      final saved = <OfflineSubtitle>[];
      var idx = 0;

      for (final sub in tracks) {
        if (cancelToken.isCancelled) break;
        idx++;
        try {
          final path =
              '${dir.path}/${safeShow}_${epTag}_${_safe(sub.lang)}_$idx'
              '${_subExt(sub.url, sub.format)}';

          // Stream to disk instead of buffering the entire response.
          final resp = await _dio.get<ResponseBody>(
            sub.url,
            options: Options(
              responseType: ResponseType.stream,
              headers: source.headers,
            ),
            cancelToken: cancelToken,
          );

          final file = File(path);
          final sink = file.openWrite();

          try {
            await sink.addStream(resp.data!.stream.map((chunk) => chunk));
            await sink.flush();
          } finally {
            await sink.close();
          }

          final len = await file.length();
          if (len == 0) {
            await file.delete();
            continue;
          }

          saved.add(
            OfflineSubtitle(
              lang: sub.lang,
              label: sub.label,
              path: path,
              isDefault: sub.isDefault,
            ),
          );
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) break;
          // Skip this track on any other error.
        }
      }

      if (saved.isEmpty) return;
      final cur = _records[rec.id];
      if (cur == null || cur.status == DownloadStatus.canceled) {
        for (final s in saved) {
          try {
            await File(s.path).delete();
          } catch (_) {}
        }
        return;
      }
      _put(cur.copyWith(subtitles: saved));
      notifyListeners();
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) return;
    } finally {
      _subtitleCancels.remove(rec.id);
    }
  }

  static List<Subtitle> _defaultSubtitleOnly(List<Subtitle> subs) {
    final def = subs.where((s) => s.isDefault).toList();
    if (def.isNotEmpty) return [def.first];
    if (subs.isNotEmpty) return [subs.first];
    return const [];
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> pause(DownloadRecord rec) async {
    if (rec.isTorrent) {
      try {
        await _torrentSvc.pause(rec.id);
      } catch (_) {}
      _put(rec.copyWith(status: DownloadStatus.paused));
      _notifyImmediate(rec.id);
      return;
    }
    final t = _tasks[rec.id];
    if (t != null) await _fileDownloader.pause(t);
  }

  /// Resume a download. After an app restart the in-memory [DownloadTask] is
  /// gone, so we re-resolve the source URL (extractor URLs expire within
  /// minutes) and enqueue a fresh task. The partial file on disk is reused via
  /// HTTP Range — background_downloader's `allowPause: true` enables this — so
  /// progress is NOT lost even though the task object is new.
  Future<void> resume(DownloadRecord rec) async {
    if (rec.isTorrent) {
      try {
        await _torrentSvc.resume(rec.id);
      } catch (_) {}
      _put(rec.copyWith(status: DownloadStatus.downloading));
      _notifyImmediate(rec.id);
      return;
    }
    final t = _tasks[rec.id];
    if (t != null) {
      await _fileDownloader.resume(t);
    } else {
      // Task object lost (restart). Re-resolve gets a fresh URL; the partial
      // file on disk is picked up by background_downloader via Range headers.
      await _resolveAndEnqueue(rec.copyWith(status: DownloadStatus.queued));
    }
  }

  Future<void> retry(DownloadRecord rec) async {
    if (rec.isTorrent || rec.status == DownloadStatus.done || rec.isActive)
      return;
    _candidates.remove(rec.id);
    await _resolveAndEnqueue(
      rec.copyWith(status: DownloadStatus.queued, error: () => null),
    );
  }

  /// Retry all failed downloads in one batch.
  Future<void> retryAllFailed() async {
    final failed = _records.values
        .where((r) => r.status == DownloadStatus.failed)
        .toList();
    for (final rec in failed) {
      await retry(rec);
    }
  }

  Future<void> cancel(DownloadRecord rec) async {
    _candidates.remove(rec.id);

    // Abort in-flight subtitle fetches so they don't silently finish after
    // the user explicitly stopped the download.
    _subtitleCancels.remove(rec.id)?.cancel('user canceled');

    _put(rec.copyWith(status: DownloadStatus.canceled, progress: 0));
    _notifyImmediate(rec.id);

    if (rec.isTorrent) {
      try {
        await _torrentSvc.cancel(rec.id);
      } catch (_) {}
      torrentProgress.remove(rec.id);
      _tasks.remove(rec.id);
      return;
    }
    _mp4Queue.removeTasksWithIds([rec.id]);
    try {
      await _fileDownloader.cancelTaskWithId(rec.id);
    } catch (_) {}
    if (!isAppleTv) {
      try {
        DownloadService.instance.invoke('cancel', {'id': rec.id});
      } catch (_) {}
    }
    _tasks.remove(rec.id);
  }

  bool _isCanceled(String id) =>
      _records[id]?.status == DownloadStatus.canceled ||
      !_records.containsKey(id);

  Future<void> delete(DownloadRecord rec) async {
    _candidates.remove(rec.id);
    _subtitleModes.remove(rec.id);
    _subtitleCancels.remove(rec.id)?.cancel('deleted');
    _lastNotifyMs.remove(rec.id);

    if (rec.isTorrent) {
      try {
        await _torrentSvc.cancel(rec.id);
      } catch (_) {}
      torrentProgress.remove(rec.id);
    }
    try {
      await _fileDownloader.cancelTaskWithId(rec.id);
    } catch (_) {}
    if (!isAppleTv) {
      try {
        DownloadService.instance.invoke('cancel', {'id': rec.id});
      } catch (_) {}
    }
    _tasks.remove(rec.id);
    for (final s in rec.subtitles) {
      try {
        final f = File(s.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _deleteMediaFile(rec.filePath);
    if (rec.supersededPath != rec.filePath) {
      await _deleteMediaFile(rec.supersededPath);
    }
    _records.remove(rec.id);
    await _box.delete(rec.id);
    notifyListeners();
  }

  Future<void> deleteAll(Iterable<DownloadRecord> recs) async {
    for (final r in recs.toList()) {
      try {
        await delete(r);
      } catch (_) {}
    }
    notifyListeners();
  }

  // ── SAF helpers ───────────────────────────────────────────────────────────

  static const MethodChannel _deviceChannel = MethodChannel(
    'com.spyou.watch_app/device',
  );

  Future<bool> _documentExists(String uri) async {
    try {
      final r = await _deviceChannel.invokeMethod<bool>('documentExists', {
        'uri': uri,
      });
      return r ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<int> _documentSize(String uri) async {
    try {
      final r = await _deviceChannel.invokeMethod<int>('documentSize', {
        'uri': uri,
      });
      return r ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<String?> _moveIntoTree(
    String localPath,
    String treeUri,
    String filename,
  ) async {
    try {
      return await _deviceChannel.invokeMethod<String>('moveIntoTree', {
        'localPath': localPath,
        'treeUri': treeUri,
        'filename': filename,
      });
    } catch (_) {
      return null;
    }
  }

  // ── Prune ─────────────────────────────────────────────────────────────────

  Future<void> pruneMissing() async {
    final gone = <String>[];
    final measured = <DownloadRecord>[];
    for (final rec in _records.values) {
      if (rec.status != DownloadStatus.done) continue;
      final fp = rec.filePath;
      if (fp == null || fp.isEmpty) continue;
      try {
        if (isUriPath(fp)) {
          if (!await _documentExists(fp)) gone.add(rec.id);
          continue;
        }
        final f = File(fp);
        if (await f.exists()) {
          if (rec.bytesTotal <= 0) {
            final len = await sizeOf(fp);
            if (len != null) measured.add(rec.copyWith(bytesTotal: len));
          }
          continue;
        }
        var storageOk = false;
        var d = f.parent;
        for (var i = 0; i < 8; i++) {
          if (await d.exists()) {
            storageOk = true;
            break;
          }
          final up = d.parent;
          if (up.path == d.path) break;
          d = up;
        }
        if (storageOk) gone.add(rec.id);
      } catch (_) {}
    }
    if (measured.isNotEmpty) {
      for (final rec in measured) _put(rec);
      notifyListeners();
    }
    if (gone.isEmpty) return;
    for (final id in gone) {
      _records.remove(id);
      _candidates.remove(id);
      _tasks.remove(id);
      _subtitleModes.remove(id);
      _lastNotifyMs.remove(id);
      await _box.delete(id);
    }
    notifyListeners();
  }

  // ── Update stream ─────────────────────────────────────────────────────────

  Future<void> _onUpdate(TaskUpdate update) async {
    final id = update.task.taskId;
    final rec = _records[id];
    if (rec == null || rec.status == DownloadStatus.canceled) return;

    if (update is TaskProgressUpdate) {
      if (update.progress >= 0) {
        _put(
          rec.copyWith(
            status: DownloadStatus.downloading,
            progress: update.progress,
            bytesTotal: update.expectedFileSize > 0
                ? update.expectedFileSize
                : null,
          ),
        );
        _notifyThrottled(id);
      }
      return;
    }

    if (update is TaskStatusUpdate) {
      switch (update.status) {
        case TaskStatus.enqueued:
          _put(rec.copyWith(status: DownloadStatus.queued));
        case TaskStatus.running:
          _put(rec.copyWith(status: DownloadStatus.downloading));
        case TaskStatus.paused:
          _put(rec.copyWith(status: DownloadStatus.paused));
        case TaskStatus.complete:
          await _finish(rec, update.task as DownloadTask, update.mimeType);
        case TaskStatus.canceled:
          _put(rec.copyWith(status: DownloadStatus.canceled));
        case TaskStatus.notFound:
        case TaskStatus.failed:
          AppLogger.instance.log(
            '[download] MP4 ${update.status.name} — ${rec.showTitle} · '
            '${rec.episodeTitle} [${rec.quality}]: '
            '${update.exception?.description ?? 'no detail'}',
            level: 'E',
          );
          if (await _tryNext(rec)) return;
          _put(
            rec.copyWith(
              status: DownloadStatus.failed,
              error: () => update.exception?.description ?? 'Download failed',
            ),
          );
        case TaskStatus.waitingToRetry:
          _put(rec.copyWith(status: DownloadStatus.downloading));
      }
      _notifyImmediate(id);
    }
  }

  Future<void> _finish(
    DownloadRecord rec,
    DownloadTask task,
    String? mimeType,
  ) async {
    String? path;

    if (task is UriDownloadTask) {
      path = task.fileUri?.toString();
      if (path == null) {
        if (await _tryNext(rec)) return;
        _put(
          rec.copyWith(
            status: DownloadStatus.failed,
            error: () => "Couldn't save to the chosen folder",
          ),
        );
        _notifyImmediate(rec.id);
        return;
      }
      final size = await _documentSize(path);
      if (size > 0 && size < 524288) {
        try {
          await _fileDownloader.uri.deleteFile(Uri.parse(path));
        } catch (_) {}
        if (await _tryNext(rec)) return;
        _put(
          rec.copyWith(
            status: DownloadStatus.failed,
            error: () => "This source can't be downloaded (stream-only / DASH)",
          ),
        );
        _notifyImmediate(rec.id);
        return;
      }
    } else {
      final mt = (mimeType ?? '').toLowerCase();
      final looksHtml = mt.contains('html') || mt.startsWith('text/');
      int size = 0;
      try {
        final f = File(await task.filePath());
        if (await f.exists()) size = await f.length();
        if (looksHtml || (size > 0 && size < 524288)) {
          if (await f.exists()) await f.delete();
          if (await _tryNext(rec)) return;
          _put(
            rec.copyWith(
              status: DownloadStatus.failed,
              error: () => 'That server returned a web page, not a video',
            ),
          );
          return;
        }
      } catch (_) {}

      final subDir = '$_sharedDir/${_safe(rec.showTitle)}';
      final loc = _downloadPrefs.locationUri;
      if (loc != null && loc.isNotEmpty && !isUriPath(loc)) {
        path = await _moveToVolume(await task.filePath(), loc, subDir);
      } else {
        try {
          path = await _fileDownloader.moveToSharedStorage(
            task,
            SharedStorage.downloads,
            directory: subDir,
          );
        } catch (_) {}
      }
      path ??= await task.filePath();
    }

    _candidates.remove(rec.id);
    await _markDone(rec, path);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _deleteMediaFile(String? fp) async {
    if (fp == null || fp.isEmpty) return;
    try {
      if (isUriPath(fp)) {
        await _fileDownloader.uri.deleteFile(Uri.parse(fp));
      } else {
        final f = File(fp);
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
        if (await f.exists()) {
          try {
            await _fileDownloader.uri.deleteFile(f.uri);
          } catch (_) {}
        }
        try {
          final dir = f.parent;
          if (await dir.exists() && await dir.list().isEmpty)
            await dir.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  @visibleForTesting
  static Future<int?> sizeOf(String? path) async {
    if (path == null || path.isEmpty || isUriPath(path)) return null;
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final len = await f.length();
      return len > 0 ? len : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _markDone(DownloadRecord rec, String? path) async {
    _subtitleModes.remove(rec.id);
    _lastNotifyMs.remove(rec.id);
    _put(
      rec.copyWith(
        status: DownloadStatus.done,
        progress: 1,
        filePath: () => path,
        bytesTotal: rec.bytesTotal > 0 ? null : await sizeOf(path),
        supersededPath: () => null,
      ),
    );
    final superseded = rec.supersededPath;
    if (superseded != null && superseded.isNotEmpty && superseded != path) {
      await _deleteMediaFile(superseded);
    }
  }

  void _put(DownloadRecord rec) {
    _records[rec.id] = rec;
    _box.put(rec.id, rec.toMap());
  }

  String _idFor(String sourceId, String showId, String episodeId) =>
      _safe('${sourceId}_${showId}_$episodeId');

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static String _ext(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    for (final e in const ['.mp4', '.mkv', '.webm', '.mov', '.m4v']) {
      if (path.endsWith(e)) return e;
    }
    return '.mp4';
  }

  static String _subExt(String url, String? format) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    for (final e in const ['.vtt', '.srt', '.ass', '.ssa', '.sub']) {
      if (path.endsWith(e)) return e;
    }
    final f = (format ?? '').toLowerCase();
    if (f.contains('srt')) return '.srt';
    if (f.contains('ass')) return '.ass';
    if (f.contains('ssa')) return '.ssa';
    return '.vtt';
  }

  static bool _isHls(VideoSource s) {
    if (s.container == SourceContainer.hls) return true;
    return (Uri.tryParse(s.url)?.path ?? s.url).toLowerCase().endsWith('.m3u8');
  }

  @visibleForTesting
  static bool isTorrentSource(VideoSource s) =>
      s.container == SourceContainer.torrent;

  Future<void> _startTorrentDownload(
    DownloadRecord rec,
    VideoSource source,
  ) async {
    _put(rec.copyWith(isTorrent: true, status: DownloadStatus.downloading));
    _notifyImmediate(rec.id);
    try {
      final loc = _downloadPrefs.locationUri;
      await _torrentSvc.enqueue(
        rec.id,
        source.url,
        saveTreeUri: loc != null && isUriPath(loc) ? loc : null,
        allowMobileData: TorrentPrefs().allowMobileData,
      );
    } catch (e) {
      final wifi = e is PlatformException && e.code == 'wifi_only';
      AppLogger.instance.log(
        'torrent start failed (${rec.showTitle}): $e',
        level: 'E',
      );
      _put(
        rec.copyWith(
          status: DownloadStatus.failed,
          error: () => wifi
              ? 'Torrents are set to Wi-Fi only (Settings › Torrents).'
              : 'Torrent download failed to start.',
        ),
      );
      _notifyImmediate(rec.id);
    }
  }

  static int _height(VideoSource s) {
    final m = RegExp(r'(\d{3,4})').firstMatch(s.quality ?? '');
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  static List<VideoSource> _ranked(List<VideoSource> sources, String quality) {
    final list = List<VideoSource>.from(sources);
    if (list.isEmpty) return const [];
    if (quality == 'best') {
      list.sort((a, b) => _height(b).compareTo(_height(a)));
      return list;
    }
    final want = int.tryParse(
      RegExp(r'(\d{3,4})').firstMatch(quality)?.group(1) ?? '',
    );
    if (want == null) {
      list.sort((a, b) => _height(b).compareTo(_height(a)));
      return list;
    }
    list.sort((a, b) {
      final da = (_height(a) - want).abs();
      final db = (_height(b) - want).abs();
      if (da != db) return da.compareTo(db);
      return _height(b).compareTo(_height(a));
    });
    return list;
  }
}
