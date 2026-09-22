import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart' show Track;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_mode.dart';
import '../../core/cache/app_image_cache.dart';
import '../../core/cast/cast_controller.dart';
import '../../core/cast/cast_proxy.dart';
import '../../core/di/injector.dart';
import '../../core/models/episode.dart';
import '../../core/models/episode_title.dart';
import '../../core/models/video_source.dart';
import '../../core/playback/external_player.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/playback/resume_store.dart';
import '../../core/playback/skip_service.dart';
import '../../core/playback/source_selection.dart';
import '../../core/playback/subtitle_language.dart';
import '../../core/playback/subtitle_search_service.dart';
import '../../core/playback/watch_history.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/torrent/torrent_util.dart';
import '../../core/tracker/tracker_hub.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/ui/badge.dart';
import '../../core/ui/brand_loader.dart';
import '../../core/ui/frosted_surface.dart';
import '../../core/ui/subtitle_language_picker.dart';
import '../detail/cubit/detail_cubit.dart' show seasonOf, seasonsOf;
import '../settings/settings_screen.dart';
import '../watch_together/ui/room_panel.dart';
import '../watch_together/watch_together_controller.dart';
import 'color_profiles.dart';
import 'drm_player_screen.dart';
import 'player_controller.dart';
import 'player_controls_config.dart';
import 'player_tv_controls.dart';
import 'seek_preview.dart';
import 'shader_presets.dart';
import 'subtitle_font_service.dart';
import 'subtitle_style.dart';

part 'player_cast_panel.dart';
part 'player_overlays.dart';
part 'player_controls_overlay.dart';
part 'player_seek_bar.dart';
part 'player_controls_widgets.dart';
part 'player_episodes_panel.dart';
part 'player_sheets.dart';

/// External players that forward HTTP request headers (Referer/Origin/Cookie) to the stream.
const List<String> kHeaderForwardingPlayers = [
  'com.mxtech.videoplayer', // MX Player (free .ad + pro)
  'com.brouken.player',     // Just Player
];

/// True when [headers] carry a gating header that the chosen external player cannot forward.
@visibleForTesting
bool headerGatedButPlayerCant(Map<String, String>? headers, String pkg) {
  if (headers == null || headers.isEmpty || pkg.isEmpty) return false;
  final gated = headers.keys.any((k) {
    final lk = k.toLowerCase();
    return lk == 'referer' || lk == 'origin' || lk == 'cookie';
  });
  if (!gated) return false;
  return !kHeaderForwardingPlayers.any(pkg.startsWith);
}

/// True when [url] is already served by a local proxy (localhost / 127.0.0.1).
@visibleForTesting
bool isLocalStreamUrl(String url) {
  final u = url.toLowerCase();
  return u.startsWith('http://localhost') ||
      u.startsWith('http://127.0.0.1') ||
      u.startsWith('https://localhost') ||
      u.startsWith('https://127.0.0.1');
}

/// True when [url] is an MPEG-DASH manifest (`.mpd`, ignoring query parameters).
@visibleForTesting
bool isDashUrl(String url) => url.toLowerCase().split('?').first.endsWith('.mpd');

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.sourceId,
    required this.resume,
    required this.resolveSources,
    this.pollSources,
    this.episodes = const [],
    this.startIndex = 0,
    this.episodesResolver,
    this.resumeEpisodeId,
    this.resumeEpisodeNumber,
    this.resumePosition = Duration.zero,
    this.history,
    this.showTitle,
    this.cover,
    this.coverHeaders,
    this.showUrl,
    this.category,
    this.malId,
    this.scrobbleTitle,
    this.tmdbId,
    this.tmdbIsTv = false,
    this.imdbId,
    this.peek = false,
    this.availableCategories = const [],
    this.joinRoomCode,
    this.playerOverride,
    this.initialSource,
  });

  final VideoSource? initialSource;
  final String? playerOverride;
  final String sourceId;
  final ResumeStore resume;
  final Future<List<VideoSource>> Function(String episodeUrl) resolveSources;
  final Future<({List<VideoSource> sources, bool done})> Function(String episodeUrl)? pollSources;
  final List<Episode> episodes;
  final int startIndex;
  final Future<List<Episode>> Function()? episodesResolver;
  final String? resumeEpisodeId;
  final double? resumeEpisodeNumber;
  final Duration resumePosition;
  final WatchHistory? history;
  final String? showTitle;
  final String? cover;
  final Map<String, String>? coverHeaders;
  final String? showUrl;
  final String? category;
  final int? malId;
  final String? scrobbleTitle;
  final int? tmdbId;
  final bool tmdbIsTv;
  final bool peek;
  final String? imdbId;
  final List<String> availableCategories;
  final String? joinRoomCode;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const MethodChannel _pipChannel = MethodChannel('zangetsu/pip');
  static const Duration _tapBurstWindow = Duration(milliseconds: 280);

  // Cached Services
  final PlaybackPrefs _prefs = sl<PlaybackPrefs>();
  final AppMode _appMode = sl<AppMode>();
  final WatchTogetherController _room = sl<WatchTogetherController>();
  final CastController _castController = sl<CastController>();
  final Floating _floating = Floating();

  String get _chosenPlayer => widget.playerOverride ?? _prefs.externalPlayerPackage;

  late final PlayerCubit _c;
  late final VoidCallback _roomListener;
  bool _attached = false;

  late final Stream<Duration> _positionBySecond = _c.player.stream.position
      .map((p) => Duration(seconds: p.inSeconds))
      .distinct();

  // Control visibility & state
  bool _controlsVisible = true;
  bool _holding = false;
  bool _portraitMode = false;
  bool _locked = false;
  int _fitIndex = 0;
  bool _ready = false;
  String? _loadError;
  DateTime? _lastBackPress;

  // Aspect ratio presets
  static const List<(BoxFit, String)> _fits = [
    (BoxFit.contain, 'Fit'),
    (BoxFit.cover, 'Fill'),
    (BoxFit.fill, 'Stretch'),
  ];

  // Timers
  Timer? _hideTimer;
  Timer? _showTimer;
  Timer? _seekLabelTimer;
  Timer? _seekDebounceTimer;
  Timer? _hudTimer;
  Timer? _upNextTimer;
  Timer? _megaFlashTimer;
  Timer? _sleepTimer;

  // Double-tap seek tracking
  int _seekAccum = 0;
  int _seekSide = 0;
  int _seekTick = 0;
  int _pendingSeek = 0;
  DateTime? _lastZoneTapAt;
  int _lastZoneTapSide = 0;
  int _zoneTapCount = 0;

  // Continuous Pinch-to-zoom (1x - 4x)
  double _zoom = 1.0;
  Offset _zoomPan = Offset.zero;
  int _zoomIndex = -1;
  bool _pinching = false;
  final Map<int, Offset> _pointers = {};
  double _pinchBaseDist = 0;
  double _pinchBaseZoom = 1.0;
  Offset _pinchBaseFocal = Offset.zero;
  Offset _pinchBasePan = Offset.zero;

  // Preferences cache for session
  Duration _duration = Duration.zero;
  late final int _seekSeconds = _prefs.doubleTapSeconds;
  late final bool _gesturesEnabled = _prefs.gestureControls;
  late final bool _swipeSeekEnabled = _prefs.swipeSeek;
  late final bool _holdSpeedEnabled = _prefs.holdSpeed;
  late final bool _skipIntroEnabled = _prefs.skipIntro;
  late final List<String> _infoFields = _prefs.playerInfoFields;
  late final bool _alwaysShowQuality = _prefs.alwaysShowQuality;
  late final bool _megaSkipEnabled = _prefs.megaSkip;
  late final int _megaSkipSeconds = _prefs.megaSkipSeconds;

  // HUD & gestures
  bool _infoPanelOpen = false;
  bool _flashing = false;
  bool _megaFlash = false;
  bool _dragIsBrightness = false;
  double _dragValue = 0;
  int _lastHudPct = -1;
  bool _hudVisible = false;
  double _hudValue = 0;
  bool _hudIsBrightness = false;

  // Horizontal seek gesture
  bool _hSeeking = false;
  Duration _hSeekStart = Duration.zero;
  Duration _hSeekTarget = Duration.zero;

  // Up Next / Sleep timer / Chat
  int _upNextLeft = 0;
  bool _upNext = false;
  bool _sleepActive = false;
  bool _sleepEndOfEpisode = false;
  bool _sleepCloseApp = false;
  bool _chatOpen = false;

  // Chromecast & TV state
  CastState _prevCastState = CastState.unavailable;
  bool _tvBarVisible = true;

  // PiP State
  bool _pipSupported = false;
  bool _inPip = false;
  StreamSubscription<PiPStatus>? _pipSub;
  final List<StreamSubscription<dynamic>> _pipStateSubs = [];

  // Stream Subscriptions & Wakelock
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  bool _wakelockOn = false;
  bool _drmHandedOff = false;

  List<DeviceOrientation> get _orientationLock => _portraitMode
      ? const [DeviceOrientation.portraitUp]
      : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];

  PlayerControlsConfig get _barConfig {
    return PlayerControlsConfig(
      top: _prefs.playerBarTop ?? PlayerControlsConfig.defaultTop,
      left: _prefs.playerBarLeft ?? PlayerControlsConfig.defaultLeft,
      right: _prefs.playerBarRight ?? PlayerControlsConfig.defaultRight,
    ).sanitised();
  }

  @override
  void initState() {
    super.initState();
    unawaited(ShaderPresets.refreshDownloaded());

    if (Platform.isAndroid && _chosenPlayer.isNotEmpty) {
      _launchExternalThenPop();
      return;
    }
    _initInApp();
  }

  void _toggleOrientation() {
    setState(() => _portraitMode = !_portraitMode);
    SystemChrome.setPreferredOrientations(_orientationLock);
    _bumpControls();
  }

  void _initInApp() {
    SystemChrome.setPreferredOrientations(_orientationLock);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (_gesturesEnabled) {
      FlutterVolumeController.updateShowSystemUI(false);
    }
    _setupPip();

    _prevCastState = _castController.state;
    _castController.removeListener(_onCastStateChanged);
    _castController.addListener(_onCastStateChanged);

    if (widget.episodesResolver != null && widget.episodes.isEmpty) {
      _resolveThenStart();
    } else {
      _startSession(widget.episodes, widget.startIndex);
    }
  }

  void _syncWakelock() {
    final want = _prefs.keepScreenOn &&
        (_c.player.state.playing || _c.player.state.buffering);
    if (want == _wakelockOn) return;
    _wakelockOn = want;
    if (want) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  // ── Chromecast ─────────────────────────────────────────────────────────────

  void _onCastStateChanged() {
    if (!mounted) return;
    final newState = _castController.state;
    final prev = _prevCastState;
    _prevCastState = newState;

    if (!_ready) return;

    if (newState == CastState.connected && prev != CastState.connected) {
      final active = _c.state.active;
      if (active == null) return;
      if (_c.player.state.playing) _c.player.pause();
      _castHandoff(active);
      if (mounted) setState(() {});
      return;
    }

    if (prev == CastState.connected && newState != CastState.connected) {
      sl<CastProxyServer>().stop();
      final resumePos = _castController.position;
      if (resumePos > Duration.zero) _c.seekTo(resumePos);
      _c.player.play();
      if (mounted) setState(() {});
    }
  }

  Future<void> _castHandoff(VideoSource active) async {
    final proxy = sl<CastProxyServer>();
    final startAt = _c.currentPosition;
    final mime = castMimeFor(active.container, active.url);

    var url = active.url;
    var subs = active.subtitles;
    try {
      final proxied = await proxy.serve(active.url, active.headers);
      if (proxied != null) {
        url = proxied;
        subs = [
          for (final s in active.subtitles)
            Subtitle(
              url: proxy.proxify(s.url) ?? s.url,
              lang: s.lang,
              label: s.label,
              format: s.format,
              isDefault: s.isDefault,
            ),
        ];
      }
    } catch (_) {}

    if (!mounted) return;
    _castController.loadCurrent(
      url: url,
      container: active.container,
      mime: mime,
      title: widget.showTitle,
      poster: widget.cover,
      subtitles: subs,
      startAt: startAt,
    );
  }

  // ── PiP Support ───────────────────────────────────────────────────────────

  Future<void> _setupPip() async {
    if (!Platform.isAndroid) return;
    try {
      final available = await _floating.isPipAvailable;
      if (!mounted || !available) return;
      setState(() => _pipSupported = true);

      _pipSub = _floating.pipStatusStream.listen((status) {
        if (!mounted) return;
        final inPip = status == PiPStatus.enabled;
        if (inPip != _inPip) setState(() => _inPip = inPip);
        if (inPip) _pushPipState();
      });

      await _pipChannel.invokeMethod('setAutoPip', _prefs.autoPip);

      _pipChannel.setMethodCallHandler((call) async {
        if (!mounted) return null;
        switch (call.method) {
          case 'play_pause':
            _c.togglePlay();
          case 'rewind':
            _c.seekBy(const Duration(seconds: -10));
          case 'forward':
            _c.seekBy(const Duration(seconds: 10));
        }
        return null;
      });

      _pushPipState();
      _pipStateSubs.addAll([
        _c.player.stream.playing.listen((_) => _pushPipState()),
        _c.player.stream.height.listen((_) => _pushPipState()),
      ]);
    } catch (_) {}
  }

  void _pushPipState() {
    if (!mounted || !_pipSupported || !_ready) return;
    _pipChannel.invokeMethod('setState', {
      'playing': _c.player.state.playing,
      'width': _c.player.state.width ?? 0,
      'height': _c.player.state.height ?? 0,
    }).catchError((_) => null);
  }

  Future<void> _enterPip() async {
    if (!_pipSupported) return;
    try {
      await _floating.enable(const ImmediatePiP(aspectRatio: Rational.landscape()));
    } catch (_) {}
  }

  // ── Session & Ext Player ──────────────────────────────────────────────────

  Future<void> _launchExternalThenPop() async {
    try {
      var eps = widget.episodes;
      if (eps.isEmpty && widget.episodesResolver != null) {
        eps = await widget.episodesResolver!();
      }
      if (eps.isEmpty) throw StateError('no episodes');
      var idx = widget.startIndex;
      if (widget.resumeEpisodeId != null) {
        var i = eps.indexWhere((e) => e.id == widget.resumeEpisodeId);
        if (i < 0 && widget.resumeEpisodeNumber != null) {
          i = eps.indexWhere((e) => e.number == widget.resumeEpisodeNumber);
        }
        if (i >= 0) idx = i;
      }
      final ep = eps[idx.clamp(0, eps.length - 1)];
      final sources = await widget.resolveSources(ep.url);
      final prefer = widget.category == 'dub' ? AudioKind.dub : AudioKind.sub;
      final src = pickDefault(sources, prefer: prefer);
      if (src == null) throw StateError('no source');

      if (isTorrentUrl(src.url)) {
        _initInApp();
        if (mounted) setState(() {});
        return;
      }

      final extPkg = _chosenPlayer;
      var playUrl = src.url;
      var launchHeaders = src.headers ?? const <String, String>{};

      if (headerGatedButPlayerCant(src.headers, extPkg)) {
        if (isDashUrl(src.url)) {
          _initInApp();
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Using the built-in player for this source.')),
            );
          }
          return;
        }
        final local = await ExternalPlayer().proxyStreamUrl(src.url, src.headers!);
        if (!mounted) return;
        if (local == null) {
          _initInApp();
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This source needs special headers — using built-in player.'),
            ),
          );
          return;
        }
        playUrl = local;
        launchHeaders = const <String, String>{};
      }

      final epNum = ep.number;
      if (epNum != null && epNum > 0 && epNum == epNum.truncateToDouble()) {
        sl<TrackerHub>().scrobble(
          malId: widget.malId,
          title: widget.scrobbleTitle,
          tmdbId: widget.tmdbId,
          tmdbIsTv: widget.tmdbIsTv,
          imdbId: widget.imdbId,
          episode: epNum.toInt(),
        );
      }

      final subs = src.subtitles
          .map((s) => {'url': s.url, 'name': s.label ?? s.lang})
          .toList();
      final title = [widget.showTitle, ep.title]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' • ');

      final res = await ExternalPlayer().launch(
        url: playUrl,
        package: _chosenPlayer,
        title: title.isEmpty ? null : title,
        headers: launchHeaders,
        subtitles: subs,
        positionMs: 0,
      );

      if (!mounted) return;
      if (res.launched) {
        _leavePlayer();
      } else {
        _initInApp();
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _initInApp();
        setState(() {});
      }
    }
  }

  Future<void> _handoffToNativeDrm(VideoSource drm) async {
    if (_drmHandedOff) return;
    _drmHandedOff = true;
    await _c.player.pause();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DrmPlayerScreen(
          sources: _c.state.sources,
          initial: drm,
          title: widget.showTitle,
          subtitle: _episodeLabelOrNull(),
        ),
      ),
    );
    _leavePlayer();
  }

  String? _episodeLabelOrNull() {
    final eps = _c.episodes;
    final i = _c.state.currentIndex;
    if (i < 0 || i >= eps.length) return null;
    final e = eps[i];
    return e.title.isNotEmpty ? e.title : null;
  }

  void _startSession(List<Episode> eps, int startIndex) {
    _c = PlayerCubit(
      sourceId: widget.sourceId,
      episodes: eps,
      resume: widget.resume,
      resolveSources: widget.resolveSources,
      pollSources: widget.pollSources,
      dio: sl<Dio>(),
      history: widget.history,
      showTitle: widget.showTitle,
      cover: widget.cover,
      coverHeaders: widget.coverHeaders,
      showUrl: widget.showUrl,
      category: widget.category,
      malId: widget.malId,
      scrobbleTitle: widget.scrobbleTitle,
      tmdbId: widget.tmdbId,
      tmdbIsTv: widget.tmdbIsTv,
      imdbId: widget.imdbId,
      peek: widget.peek,
      availableCategories: widget.availableCategories,
      initialResume: widget.resumePosition,
      initialSource: widget.initialSource,
      onDrmSource: _handoffToNativeDrm,
    )..init(startIndex);

    _playingSub = _c.player.stream.playing.listen((_) => _syncWakelock());
    _bufferingSub = _c.player.stream.buffering.listen((_) => _syncWakelock());
    _syncWakelock();

    _room.attachPlayer(
      localPosition: () => _c.player.state.position,
      onApplyRemote: (playing, pos, rate) =>
          _c.applyRemote(playing: playing, position: pos, rate: rate),
      onEpisodeChange: (r) {
        var i = _c.episodes.indexWhere((e) => e.id == r.episodeId);
        if (i < 0 && r.episodeNumber != null) {
          i = _c.episodes.indexWhere((e) => e.number == r.episodeNumber);
        }
        if (i >= 0 && i != _c.state.currentIndex) _c.openEpisode(i, fromRoom: true);
      },
      content: {
        'sourceId': _c.sourceId,
        'sourceLabel': widget.showTitle ?? '',
        'showUrl': widget.showUrl ?? '',
        'showTitle': widget.showTitle ?? '',
        'cover': widget.cover ?? '',
        'episodeId': _c.currentEpisode.id,
        'episodeNumber': _c.currentEpisode.number,
        'episodeUrl': _c.currentEpisode.url,
        'category': widget.category ?? 'sub',
        'malId': widget.malId,
        'tmdbId': widget.tmdbId,
        'positionMs': _c.player.state.position.inMilliseconds,
      },
    );

    _wireRoom(_room);
    if (widget.joinRoomCode != null) _room.join(widget.joinRoomCode!);

    _completedSub = _c.player.stream.completed.listen((done) {
      if (done) _onEpisodeComplete();
    });

    if (mounted) setState(() => _ready = true);
    _scheduleHide();
  }

  void _wireRoom(WatchTogetherController room) {
    _roomListener = () {
      _c.roomRole = room.role;
      if (mounted) setState(() {});
    };
    room.addListener(_roomListener);
    _attached = true;
    _c.onLocalPlayback = (event, pos) {
      switch (event) {
        case 'play':
          room.broadcastPlay(pos);
        case 'pause':
          room.broadcastPause(pos);
        case 'seek':
          room.broadcastSeek(pos);
        case 'episode':
          final ep = _c.currentEpisode;
          room.broadcastEpisode(
            episodeId: ep.id,
            number: ep.number,
            episodeUrl: ep.url,
          );
      }
    };
  }

  Future<void> _resolveThenStart() async {
    try {
      final eps = await widget.episodesResolver!();
      if (!mounted) return;
      if (eps.isEmpty) {
        _failJoinOrPop();
        return;
      }
      var idx = 0;
      if (widget.resumeEpisodeId != null) {
        var i = eps.indexWhere((e) => e.id == widget.resumeEpisodeId);
        if (i < 0 && widget.resumeEpisodeNumber != null) {
          i = eps.indexWhere((e) => e.number == widget.resumeEpisodeNumber);
        }
        if (i >= 0) idx = i;
      }
      _startSession(eps, idx);
    } catch (_) {
      if (mounted) _failJoinOrPop();
    }
  }

  void _failJoinOrPop() {
    if (widget.joinRoomCode != null) {
      final sourceInstalled = sl<SourceRepository>().hasSource(widget.sourceId);
      setState(() => _loadError = sourceInstalled
          ? "Couldn't load this show right now.\n\n"
              'The source is available, but the episode list came back empty. Tap Back and try again.'
          : "Couldn't open this room's video source on your device.\n\n"
              "The host is watching on a source you don't have installed. Add it "
              'from Settings, or ask the host to use a built-in source.');
    } else {
      _leavePlayer();
    }
  }

  void _leavePlayer() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _handleCloseRequest() async {
    switch (_prefs.closeConfirmation) {
      case 'confirm':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Close video?'),
            content: const Text('Are you sure you want to close the video?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close')),
            ],
          ),
        );
        if (ok == true) _leavePlayer();
      case 'direct':
        _leavePlayer();
      default:
        final now = DateTime.now();
        if (_lastBackPress != null && now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          _leavePlayer();
          return;
        }
        _lastBackPress = now;
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
    }
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _cancelAllSubscriptions();

    _castController.removeListener(_onCastStateChanged);

    if (_pipSupported) {
      _pipChannel.setMethodCallHandler(null);
      _pipChannel.invokeMethod('setAutoPip', false);
    }

    if (_gesturesEnabled) {
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
      FlutterVolumeController.updateShowSystemUI(true);
    }

    WakelockPlus.disable();

    if (_ready) _c.close();

    if (_attached) {
      _room.removeListener(_roomListener);
      _room.detachPlayer();
    }

    SystemChrome.setPreferredOrientations(
      _appMode.isTv
          ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const [DeviceOrientation.portraitUp],
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _cancelAllTimers() {
    _hideTimer?.cancel();
    _showTimer?.cancel();
    _seekLabelTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _hudTimer?.cancel();
    _upNextTimer?.cancel();
    _megaFlashTimer?.cancel();
    _sleepTimer?.cancel();
  }

  void _cancelAllSubscriptions() {
    _completedSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _pipSub?.cancel();
    for (final s in _pipStateSubs) {
      s.cancel();
    }
    _pipStateSubs.clear();
  }

  // ── Visibility & Gestures ─────────────────────────────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _c.player.state.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _bumpControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _tapZone(int dir) {
    final now = DateTime.now();
    final last = _lastZoneTapAt;
    final chained = last != null && _lastZoneTapSide == dir && now.difference(last) < _tapBurstWindow;
    _lastZoneTapAt = now;
    _lastZoneTapSide = dir;
    _zoneTapCount = chained ? _zoneTapCount + 1 : 1;

    if (dir == 0) {
      _cancelPendingShow();
      _toggleControls();
      return;
    }

    if (_zoneTapCount >= 2) {
      _cancelPendingShow();
      _seekZone(dir);
      return;
    }

    if (_controlsVisible) {
      _toggleControls();
    } else {
      _showTimer?.cancel();
      _showTimer = Timer(_tapBurstWindow, () {
        if (mounted) _bumpControls();
      });
    }
  }

  void _cancelPendingShow() {
    _showTimer?.cancel();
    _showTimer = null;
  }

  void _accumSeek(int dir) {
    HapticFeedback.lightImpact();
    if (_seekSide != dir) {
      _flushPendingSeek();
      _seekAccum = 0;
    }
    _seekSide = dir;
    _seekAccum += _seekSeconds;
    _pendingSeek += dir * _seekSeconds;
    _seekTick++;
    _seekLabelTimer?.cancel();
    setState(() {});

    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 350), _flushPendingSeek);
    _seekLabelTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _seekSide = 0;
          _seekAccum = 0;
        });
      }
    });

    if (_controlsVisible) _scheduleHide();
  }

  void _flushPendingSeek() {
    _seekDebounceTimer?.cancel();
    if (_pendingSeek != 0) {
      _c.seekBy(Duration(seconds: _pendingSeek));
      _pendingSeek = 0;
    }
  }

  void _seekZone(int dir) => _accumSeek(dir);

  Future<void> _onVDragStart(DragStartDetails d) async {
    if (!_gesturesEnabled) return;
    _lastHudPct = -1;
    final screenWidth = MediaQuery.sizeOf(context).width;
    _dragIsBrightness = d.localPosition.dx < screenWidth / 2;

    if (_dragIsBrightness) {
      try {
        _dragValue = await ScreenBrightness.instance.application;
      } catch (_) {
        _dragValue = 0.5;
      }
    } else {
      final boost = _prefs.volumeBoost;
      final double combined = boost > 100
          ? boost / 100.0
          : (await FlutterVolumeController.getVolume()) ?? 0.5;
      _dragValue = (combined / 2).clamp(0.0, 1.0);
    }
  }

  void _onVDragUpdate(DragUpdateDetails d) {
    if (!_gesturesEnabled || _pinching) return;
    final h = MediaQuery.sizeOf(context).height;
    _dragValue = (_dragValue - d.primaryDelta! / (h * 0.7)).clamp(0.0, 1.0);

    if (_dragIsBrightness) {
      ScreenBrightness.instance.setApplicationScreenBrightness(_dragValue).catchError((_) {});
    } else {
      final combined = (_dragValue * 2).clamp(0.0, 2.0);
      FlutterVolumeController.setVolume(combined.clamp(0.0, 1.0));
      final boost = combined <= 1.0 ? 100 : (combined * 100).round();
      if (boost != _prefs.volumeBoost) _c.setVolumeBoost(boost);
    }

    final pct = ((_dragIsBrightness ? 1 : 2) * _dragValue * 100).round();
    if (_lastHudPct >= 0) {
      for (final b in (_dragIsBrightness ? const [0, 100] : const [0, 100, 200])) {
        if ((_lastHudPct - b) * (pct - b) <= 0 && _lastHudPct != pct) {
          HapticFeedback.selectionClick();
          break;
        }
      }
    }
    _lastHudPct = pct;

    setState(() {
      _hudVisible = true;
      _hudValue = _dragValue;
      _hudIsBrightness = _dragIsBrightness;
    });
  }

  void _onVDragEnd(DragEndDetails d) {
    if (!_gesturesEnabled) return;
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  void _onHDragStart(DragStartDetails d) {
    if (!_swipeSeekEnabled || _duration <= Duration.zero) return;
    _hSeekStart = _c.player.state.position;
    _hSeekTarget = _hSeekStart;
    setState(() => _hSeeking = true);
  }

  void _onHDragUpdate(DragUpdateDetails d) {
    if (!_hSeeking || _pinching) return;
    final w = MediaQuery.sizeOf(context).width;
    final perPx = _duration.inMilliseconds / w;
    final deltaMs = (d.primaryDelta! * perPx).round();
    var t = (_hSeekTarget.inMilliseconds + deltaMs).clamp(0, _duration.inMilliseconds);
    setState(() => _hSeekTarget = Duration(milliseconds: t));
  }

  void _onHDragEnd(DragEndDetails d) {
    if (!_hSeeking) return;
    _c.seekTo(_hSeekTarget);
    setState(() => _hSeeking = false);
    _bumpControls();
  }

  // ── Pinch to zoom handlers ────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && !_locked) _startPinch();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pinching && _pointers.length >= 2) _updatePinch();
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _pinching) _endPinch();
  }

  void _startPinch() {
    final p = _pointers.values.toList();
    _pinchBaseDist = (p[0] - p[1]).distance;
    _pinchBaseFocal = Offset((p[0].dx + p[1].dx) / 2, (p[0].dy + p[1].dy) / 2);
    _pinchBaseZoom = _zoom;
    _pinchBasePan = _zoomPan;
    setState(() {
      _pinching = true;
      _hSeeking = false;
      _hudVisible = false;
    });
  }

  void _updatePinch() {
    if (_pinchBaseDist <= 0) return;
    final p = _pointers.values.toList();
    final dist = (p[0] - p[1]).distance;
    final focal = Offset((p[0].dx + p[1].dx) / 2, (p[0].dy + p[1].dy) / 2);
    final z = (_pinchBaseZoom * dist / _pinchBaseDist).clamp(1.0, 4.0);
    setState(() {
      _zoom = z;
      _zoomPan = _clampPan(_pinchBasePan + (focal - _pinchBaseFocal), z);
    });
  }

  void _endPinch() {
    setState(() {
      _pinching = false;
      if (_zoom < 1.08) {
        _zoom = 1.0;
        _zoomPan = Offset.zero;
      }
    });
  }

  Offset _clampPan(Offset pan, double zoom) {
    final size = MediaQuery.sizeOf(context);
    final maxX = (zoom - 1) * size.width / 2;
    final maxY = (zoom - 1) * size.height / 2;
    return Offset(pan.dx.clamp(-maxX, maxX).toDouble(), pan.dy.clamp(-maxY, maxY).toDouble());
  }

  // ── Actions & Dialogs ─────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    final wasPlaying = _c.player.state.playing;
    if (wasPlaying) _c.togglePlay();

    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;

    await SystemChrome.setPreferredOrientations(_orientationLock);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted) return;

    if (wasPlaying && !_c.player.state.playing) _c.togglePlay();
    _bumpControls();
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      if (_locked) {
        _controlsVisible = false;
      } else {
        _controlsVisible = true;
        _scheduleHide();
      }
    });
  }

  void _cycleFit() {
    setState(() => _fitIndex = (_fitIndex + 1) % _fits.length);
    _bumpControls();
  }

  Widget? _skipButtonFor(Duration pos) {
    if (!_skipIntroEnabled) return null;
    for (final iv in _c.currentSkips) {
      if (pos >= iv.start && pos < iv.end - const Duration(seconds: 1)) {
        return _SkipButton(
          label: isRecapSkip(iv.type) ? 'Skip Recap' : 'Skip',
          onTap: () {
            _c.seekTo(iv.end);
            _bumpControls();
          },
        );
      }
    }
    return null;
  }

  void _megaSkip() {
    _c.seekBy(Duration(seconds: _megaSkipSeconds));
    _bumpControls();
    _megaFlashTimer?.cancel();
    setState(() => _megaFlash = true);
    _megaFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _megaFlash = false);
    });
  }

  Future<void> _captureScreenshot() async {
    setState(() => _flashing = true);
    Future.delayed(const Duration(milliseconds: 130), () {
      if (mounted) setState(() => _flashing = false);
    });
    await _c.captureScreenshot();
    _bumpControls();
  }

  void _onEpisodeComplete() {
    if (_sleepEndOfEpisode) {
      _c.player.pause();
      setState(() {
        _sleepActive = false;
        _sleepEndOfEpisode = false;
      });
      if (_sleepCloseApp) SystemNavigator.pop();
      return;
    }
    final hasNext = _c.state.currentIndex + 1 < _c.episodes.length;
    if (!hasNext || !_prefs.autoplayNext) return;

    _upNextTimer?.cancel();
    setState(() {
      _upNext = true;
      _upNextLeft = 5;
      _controlsVisible = false;
    });

    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _upNextLeft -= 1);
      if (_upNextLeft <= 0) {
        t.cancel();
        _playUpNext();
      }
    });
  }

  void _playUpNext() {
    _upNextTimer?.cancel();
    setState(() => _upNext = false);
    _c.playNext(auto: true);
  }

  void _dismissUpNext() {
    _upNextTimer?.cancel();
    setState(() => _upNext = false);
  }

  void _openEnhanceSheet() {
    if (!ShaderPresets.downloaded) {
      _sheet<void>(
        _SheetColumn(
          header: 'Anime4K Enhancement',
          children: [
            _SheetRow(
              label: 'Download in Settings',
              subtitle: 'Get the Anime4K shaders (~0.6 MB), then turn it on',
              active: false,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }
    final currentStyle = _prefs.videoShaderStyle;
    final currentTier = _prefs.videoShaderTier;
    _sheet<void>(
      _SheetColumn(
        header: 'Anime4K Enhancement',
        children: [
          for (final s in ShaderPresets.styles)
            _SheetRow(
              label: s.label,
              subtitle: s.description,
              active: s.id == currentStyle,
              onTap: () {
                Navigator.pop(context);
                _c.setShaderStyle(s.id);
                if (mounted) setState(() {});
                _bumpControls();
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'GPU TIER',
              style: AppText.caption.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final t in ShaderPresets.tiers)
            _SheetRow(
              label: ShaderPresets.tierLabel(t),
              subtitle: ShaderPresets.tierDescription(t),
              active: t == currentTier,
              onTap: () {
                Navigator.pop(context);
                _c.setShaderTier(t);
                if (mounted) setState(() {});
                _bumpControls();
              },
            ),
        ],
      ),
    );
  }

  void _openColorProfileSheet() {
    _sheet<void>(_ColorSheet(controller: _c, onInteract: _bumpControls));
  }

  void _openEpisodesPanel() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Episodes',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, _, _) => Align(
        alignment: Alignment.centerRight,
        child: _EpisodesPanel(
          episodes: _c.episodes,
          currentIndex: _c.state.currentIndex,
          cover: widget.cover,
          coverHeaders: widget.coverHeaders,
          fillerEps: _c.fillerEpisodes.value,
          onSelect: (i) {
            Navigator.pop(ctx);
            if (i != _c.state.currentIndex) _c.openEpisode(i);
            _bumpControls();
          },
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }

  void _openSleepSheet() {
    void choose(Duration? d, {bool endOfEpisode = false}) {
      Navigator.pop(context);
      _setSleep(d, endOfEpisode: endOfEpisode);
    }

    _sheet<void>(
      StatefulBuilder(
        builder: (context, setSheet) => _SheetColumn(
          header: 'Sleep timer',
          children: [
            _SheetRow(
              label: 'Off',
              active: !_sleepActive,
              onTap: () => choose(null),
            ),
            for (final m in const [5, 15, 30, 45, 60])
              _SheetRow(
                label: '$m minutes',
                active: false,
                onTap: () => choose(Duration(minutes: m)),
              ),
            _SheetRow(
              label: 'End of episode',
              active: _sleepEndOfEpisode,
              onTap: () => choose(null, endOfEpisode: true),
            ),
            _SheetRow(
              label: 'Close app when timer ends',
              subtitle: 'Exit the app to save battery',
              active: false,
              toggleValue: _sleepCloseApp,
              onTap: () => setSheet(() => _sleepCloseApp = !_sleepCloseApp),
            ),
          ],
        ),
      ),
    );
  }

  void _setSleep(Duration? d, {bool endOfEpisode = false}) {
    _sleepTimer?.cancel();
    setState(() {
      _sleepEndOfEpisode = endOfEpisode;
      _sleepActive = endOfEpisode || d != null;
    });

    if (d != null) {
      _sleepTimer = Timer(d, () {
        if (!mounted) return;
        _c.player.pause();
        setState(() => _sleepActive = false);
        if (_sleepCloseApp) SystemNavigator.pop();
      });
    }

    final msg = endOfEpisode
        ? 'Sleep timer: end of this episode'
        : d != null
            ? 'Sleep timer set for ${d.inMinutes} min${_sleepCloseApp ? ' · closes the app' : ''}'
            : 'Sleep timer off';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    _bumpControls();
  }

  static String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  Future<T?> _sheet<T>(Widget child) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SheetSurface(child: SafeArea(top: false, child: child)),
    );
  }

  void _openSpeedSheet() {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final current = _c.player.state.rate;
    _sheet<void>(
      _SheetChips(
        header: 'Playback Speed',
        labels: [for (final r in rates) r == 1.0 ? 'Normal' : '${r}x'],
        selected: rates.indexWhere((r) => (current - r).abs() < 0.01),
        onSelect: (i) {
          Navigator.pop(context);
          _c.setRateRemembered(rates[i]);
          _bumpControls();
        },
      ),
    );
  }

  static String _shortDecoder(String mode) => switch (mode) {
    'direct' => 'HW',
    'sw' => 'SW',
    'auto' => 'AUTO',
    _ => 'HW+',
  };

  void _openDecoderSheet() {
    const modes = [
      ('copy', 'Hardware+ (recommended)'),
      ('direct', 'Hardware (faster)'),
      ('sw', 'Software (most compatible)'),
      ('auto', 'Auto'),
    ];
    final current = _c.decoderMode;
    _sheet<void>(
      _SheetColumn(
        header: 'Video decoder',
        children: [
          for (final (mode, label) in modes)
            _SheetRow(
              label: label,
              active: current == mode,
              onTap: () {
                Navigator.pop(context);
                _c.setDecoder(mode);
                _bumpControls();
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    );
  }

  SubtitleViewConfiguration _subtitleConfig() {
    final pos = _prefs.subtitlePosition.clamp(0, 100);
    final bottom = 16.0 + (100 - pos) * 3.0;
    return SubtitleViewConfiguration(
      textAlign: TextAlign.center,
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
      style: buildSubtitleTextStyle(_prefs, fontSize: 32.0 * _prefs.subtitleScale),
    );
  }

  void _openAudioSubsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SheetSurface(
        blur: true,
        opacity: 0.82,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: _AudioSubsSheet(
            controller: _c,
            onInteract: _bumpControls,
            onLoadFile: () {
              Navigator.pop(context);
              _loadSubtitleFromFile();
            },
            onSearchOnline: () {
              Navigator.pop(context);
              _openOnlineSubtitleSheet();
            },
            onTranslate: () {
              Navigator.pop(context);
              _openTranslateSheet();
            },
          ),
        ),
      ),
    );
  }

  void _openTranslateSheet() {
    final pref = _prefs.translateSubtitleTo;
    _sheet<void>(
      _SheetColumn(
        header: 'Translate subtitles to',
        children: [
          for (final lang in kSubtitleLanguages)
            _SheetRow(
              label: lang.name,
              active: lang.iso1 == pref,
              onTap: () {
                Navigator.pop(context);
                _prefs.setTranslateSubtitleTo(lang.iso1);
                _c.translateCurrentSub(lang.iso1);
                _bumpControls();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _loadSubtitleFromFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa', 'sub'],
      );
      final path = file?.path;
      if (path != null) {
        await _c.setSubtitleFromFile(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load subtitle: $e')),
        );
      }
    }
    _bumpControls();
  }

  void _openOnlineSubtitleSheet() {
    final initialQuery = (widget.showTitle?.trim().isNotEmpty ?? false)
        ? widget.showTitle!.trim()
        : (widget.scrobbleTitle?.trim() ?? '');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SheetSurface(
        blur: true,
        opacity: 0.82,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: _OnlineSubtitleSheet(
            initialQuery: initialQuery,
            initialLanguage: _prefs.preferredSubtitleLanguage.isEmpty
                ? 'en'
                : _prefs.preferredSubtitleLanguage,
            imdbId: widget.imdbId,
            tmdbId: widget.tmdbId,
            onApply: (path) async {
              await _c.setSubtitleFromFile(path);
              _bumpControls();
            },
          ),
        ),
      ),
    );
  }

  void _openQualitySheet() {
    final List<Widget> rows;
    if (_c.state.qualities.isNotEmpty) {
      rows = [
        _SheetRow(
          label: 'Auto',
          active: _c.state.activeQuality == null,
          onTap: () {
            Navigator.pop(context);
            _c.chooseQuality(null);
            _bumpControls();
          },
        ),
        for (final v in _c.state.qualities)
          _SheetRow(
            label: v.quality,
            active: _c.state.activeQuality?.url == v.url,
            onTap: () {
              Navigator.pop(context);
              _c.chooseQuality(v);
              _bumpControls();
            },
          ),
      ];
    } else if (_c.mediaVideoTracks.length > 1) {
      rows = [
        for (final t in _c.mediaVideoTracks)
          _SheetRow(
            label: '${t.h}p',
            active: _c.selectedVideoTrack?.id == t.id,
            onTap: () {
              Navigator.pop(context);
              _c.selectVideoTrack(t);
              _bumpControls();
            },
          ),
      ];
    } else {
      return;
    }
    if (rows.isEmpty) return;
    _sheet<void>(_SheetColumn(header: 'Quality', children: rows));
  }

  static String _sourceLabelWithQuality(String label, String? quality) {
    if (quality == null || quality.isEmpty) return label;
    if (label.toLowerCase().contains(quality.toLowerCase())) return label;
    return '$label • $quality';
  }

  void _openSourceSheet() {
    final kinds = availableKinds(_c.state.sources);
    _sheet<void>(
      _SheetColumn(
        header: 'Sources',
        children: [
          for (final k in kinds)
            for (final s in sortByQuality(sourcesForKind(_c.state.sources, k)))
              _SheetRow(
                label: s.label?.isNotEmpty == true
                    ? _sourceLabelWithQuality(s.label!, s.quality)
                    : '${k != AudioKind.unknown ? '${k.name.toUpperCase()} • ' : ''}'
                        '${s.quality?.isNotEmpty == true ? s.quality : s.container.name}',
                active: s == _c.state.active,
                onTap: () {
                  Navigator.pop(context);
                  _c.selectSource(s);
                  _bumpControls();
                },
              ),
        ],
      ),
    );
  }

  // ── Sub-builders ──────────────────────────────────────────────────────────

  Widget _buildLoadingBackdrop(String label, {String? thumb}) {
    final img = (thumb?.trim().isNotEmpty ?? false) ? thumb!.trim() : (widget.cover ?? '').trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (img.isNotEmpty)
          CachedNetworkImage(
            imageUrl: img,
            httpHeaders: widget.coverHeaders,
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            errorWidget: (c, u, e) => const ColoredBox(color: Colors.black),
            placeholder: (c, u) => const ColoredBox(color: Colors.black),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Color(0xCC000000)],
            ),
          ),
        ),
        Center(child: BrandLoader(label: label)),
      ],
    );
  }

  Widget _buildUpNextCard() {
    final nextIdx = _c.state.currentIndex + 1;
    final next = nextIdx < _c.episodes.length ? _c.episodes[nextIdx] : null;
    final epNum = next?.number?.toInt() ?? (nextIdx + 1);
    final name = next?.title.trim() ?? '';
    final hasName = name.isNotEmpty && name.toLowerCase() != 'episode $epNum';
    final img = (next?.thumbnail?.trim().isNotEmpty ?? false)
        ? next!.thumbnail!.trim()
        : (widget.cover ?? '');

    return Align(
      alignment: const Alignment(0.95, 0.7),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (img.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: img,
                    httpHeaders: widget.coverHeaders,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const ColoredBox(color: Colors.white10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text('Up next in $_upNextLeft', style: AppText.caption.copyWith(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              hasName ? 'E$epNum · $name' : 'Episode $epNum',
              style: AppText.headline.copyWith(color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _playUpNext,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 4),
                          Text('Play now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Dismiss',
                  child: GestureDetector(
                    onTap: _dismissUpNext,
                    child: Container(
                      height: 38,
                      width: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutroNextButton() {
    final hasNext = _c.state.currentIndex + 1 < _c.episodes.length;
    if (!hasNext) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: _positionBySecond,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = _c.player.state.duration;
        final remaining = dur - pos;
        final show = dur > Duration.zero && remaining <= const Duration(seconds: 75);
        if (!show) return const SizedBox.shrink();
        return Positioned(
          bottom: 16,
          right: 16,
          child: GestureDetector(
            onTap: _playUpNext,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.hairline, width: 0.5),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.skip_next, color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text('Next Episode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Main Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, color: Colors.white54, size: 44),
                  const SizedBox(height: 14),
                  Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.4)),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildLoadingBackdrop('Loading…'),
      );
    }

    final scaffold = TooltipTheme(
      data: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: AppText.caption.copyWith(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocBuilder<PlayerCubit, PlayerState>(
          bloc: _c,
          builder: (context, state) {
            if (_inPip) {
              return Center(
                child: Video(
                  controller: _c.videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
              );
            }
            if (state.loadingSources) {
              return _buildLoadingBackdrop('Finding the best source…', thumb: _c.currentEpisode.thumbnail);
            }
            if (state.torrentPhase != null) {
              return _buildLoadingBackdrop(state.torrentPhase!, thumb: _c.currentEpisode.thumbnail);
            }
            if (state.error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40, color: AppColors.textTertiary),
                      const SizedBox(height: 12),
                      Text(state.error!, style: AppText.body, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _c.openEpisode(state.currentIndex),
                        child: Text('Try again', style: AppText.body.copyWith(color: AppColors.accent)),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (_zoomIndex != state.currentIndex) {
              _zoomIndex = state.currentIndex;
              _zoom = 1.0;
              _zoomPan = Offset.zero;
            }

            return Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Video Render Layer
                  Center(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _c.subtitleStyleRev,
                      builder: (context, _, _) => Transform.translate(
                        offset: _zoomPan,
                        child: Transform.scale(
                          scale: _zoom,
                          child: Video(
                            controller: _c.videoController,
                            controls: NoVideoControls,
                            fit: _fits[_fitIndex].$1,
                            subtitleViewConfiguration: _subtitleConfig(),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 1b. Poster Fade-out
                  Positioned.fill(
                    child: StreamBuilder<int?>(
                      stream: _c.player.stream.width,
                      initialData: _c.player.state.width,
                      builder: (context, snap) {
                        final hasFrame = (snap.data ?? 0) > 0;
                        final img = (_c.currentEpisode.thumbnail?.trim().isNotEmpty ?? false)
                            ? _c.currentEpisode.thumbnail!.trim()
                            : (widget.cover ?? '');
                        return IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: hasFrame || img.isEmpty ? 0 : 1,
                            duration: const Duration(milliseconds: 350),
                            child: img.isEmpty
                                ? const ColoredBox(color: Colors.black)
                                : Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: img,
                                        httpHeaders: widget.coverHeaders,
                                        fit: BoxFit.cover,
                                        errorWidget: (c, u, e) => const ColoredBox(color: Colors.black),
                                      ),
                                      const DecoratedBox(
                                        decoration: BoxDecoration(color: Color(0x33000000)),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                  ),

                  // 2. Gesture Surface / TV Controls
                  if (_appMode.isTv)
                    Positioned.fill(
                      child: PlayerTvControls(
                        onTogglePlay: _c.togglePlay,
                        onSeekBy: _c.seekBy,
                        onSpeed: _openSpeedSheet,
                        onAudioSubs: _openAudioSubsSheet,
                        onQuality: _openQualitySheet,
                        showQuality: state.qualities.isNotEmpty || _c.mediaVideoTracks.length > 1,
                        onSources: _openSourceSheet,
                        onFit: _cycleFit,
                        onNext: state.currentIndex + 1 < _c.episodes.length ? () => _c.playNext() : null,
                        onBack: () => Navigator.of(context).maybePop(),
                        playingStream: _c.player.stream.playing,
                        initialPlaying: _c.player.state.playing,
                        barVisible: _tvBarVisible,
                        onBarChange: (v) => setState(() => _tvBarVisible = v),
                        positionStream: _c.player.stream.position,
                        durationStream: _c.player.stream.duration,
                        initialPosition: _c.player.state.position,
                        initialDuration: _c.player.state.duration,
                        skipInfoFor: (pos) {
                          for (final iv in _c.currentSkips) {
                            if (pos >= iv.start && pos < iv.end - const Duration(seconds: 1)) {
                              return (
                                label: isRecapSkip(iv.type)
                                    ? 'Skip recap'
                                    : iv.type == 'ed'
                                        ? 'Skip ending'
                                        : 'Skip opening',
                                onSkip: () => _c.seekTo(iv.end),
                              );
                            }
                          }
                          return null;
                        },
                      ),
                    )
                  else if (_locked)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleControls,
                      ),
                    )
                  else
                    Positioned.fill(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart: _holdSpeedEnabled
                                ? (_) {
                                    _c.setRate(2.0);
                                    setState(() => _holding = true);
                                  }
                                : null,
                            onLongPressEnd: _holdSpeedEnabled
                                ? (_) {
                                    _c.setRate(1.0);
                                    setState(() => _holding = false);
                                  }
                                : null,
                            onVerticalDragStart: _onVDragStart,
                            onVerticalDragUpdate: _onVDragUpdate,
                            onVerticalDragEnd: _onVDragEnd,
                            onHorizontalDragStart: _swipeSeekEnabled ? _onHDragStart : null,
                            onHorizontalDragUpdate: _swipeSeekEnabled ? _onHDragUpdate : null,
                            onHorizontalDragEnd: _swipeSeekEnabled ? _onHDragEnd : null,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => _tapZone(-1),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => _tapZone(0),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => _tapZone(1),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // 3. Buffering Indicator
                  // 3. Buffering Indicator
                  StreamBuilder<bool>(
                    stream: _c.player.stream.buffering,
                    builder: (context, snap) {
                      final show = (snap.data ?? false) && !_controlsVisible;
                      return IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: show ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: TickerMode(
                            enabled: show,
                            child: Center(
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  color: AppColors.accent,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // 3b. Status Toast
                  ValueListenableBuilder<String?>(
                    valueListenable: _c.toast,
                    builder: (context, msg, _) {
                      if (msg == null) return const SizedBox.shrink();
                      return Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                msg,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // 4. Double-Tap Indicator
                  if (_seekSide != 0)
                    _SeekIndicator(
                      key: ValueKey(_seekTick),
                      side: _seekSide,
                      accumSeconds: _seekAccum,
                    ),

                  // 4b. Brightness / Volume HUD
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _hudVisible ? 1 : 0,
                      duration: Duration(milliseconds: _hudVisible ? 120 : 260),
                      curve: Curves.easeOut,
                      child: Align(
                        alignment: _hudIsBrightness
                            ? const Alignment(0.88, 0.0)
                            : const Alignment(-0.88, 0.0),
                        child: _AdjustHud(value: _hudValue, isBrightness: _hudIsBrightness),
                      ),
                    ),
                  ),

                  // 5. 2x Indicator
                  if (_holding)
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 5),
                                Text(
                                  '2×',
                                  style: AppText.caption.copyWith(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.1,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 4c. Horizontal Seek Preview
                  if (_hSeeking)
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          child: Text(
                            '${_fmtDur(_hSeekTarget)} / ${_fmtDur(_duration)}',
                            style: AppText.headline.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ),

                  // 6. Primary Overlay Controls
                  if (!_appMode.isTv && !_locked)
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: Duration(milliseconds: _controlsVisible ? 160 : 240),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: _ControlsOverlay(
                          controller: _c,
                          state: state,
                          visible: _controlsVisible,
                          showTitle: widget.showTitle,
                          duration: _duration,
                          zoomLabel: _fits[_fitIndex].$2,
                          onDurationChanged: (d) {
                            if (mounted && d != _duration) {
                              setState(() => _duration = d);
                            }
                          },
                          onInteract: _bumpControls,
                          onRotate: _toggleOrientation,
                          portraitMode: _portraitMode,
                          onBack: () => Navigator.of(context).maybePop(),
                          onSpeed: _openSpeedSheet,
                          onAudioSubs: _openAudioSubsSheet,
                          onQuality: _openQualitySheet,
                          onSources: _openSourceSheet,
                          onLock: _toggleLock,
                          onSettings: _openSettings,
                          barConfig: _barConfig,
                          onZoom: _cycleFit,
                          onPip: _pipSupported ? _enterPip : null,
                          onSleep: _openSleepSheet,
                          sleepActive: _sleepActive,
                          decoderLabel: _shortDecoder(_c.decoderMode),
                          onDecoder: _openDecoderSheet,
                          onEpisodes: _c.episodes.length > 1 ? _openEpisodesPanel : null,
                          onPrev: _c.state.currentIndex > 0
                              ? () {
                                  _c.playPrevious();
                                  _bumpControls();
                                }
                              : null,
                          megaSkipEnabled: _megaSkipEnabled,
                          megaSkipSeconds: _megaSkipSeconds,
                          onMegaSkip: _megaSkip,
                          onChat: (_room.room != null) ? () => setState(() => _chatOpen = !_chatOpen) : null,
                          onInfo: _infoFields.isEmpty
                              ? null
                              : () {
                                  setState(() => _infoPanelOpen = !_infoPanelOpen);
                                  _bumpControls();
                                },
                          infoOpen: _infoPanelOpen,
                          showQuality: _alwaysShowQuality,
                          onScreenshot: _captureScreenshot,
                          onEnhance: _openEnhanceSheet,
                          enhanceActive: _prefs.videoShaderStyle != 'off',
                          onColorProfile: _openColorProfileSheet,
                        ),
                      ),
                    )
                  else if (!_appMode.isTv)
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: Duration(milliseconds: _controlsVisible ? 160 : 240),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RoundIconButton(
                                icon: Icons.lock_rounded,
                                onTap: _toggleLock,
                                semanticLabel: 'Unlock controls',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap to unlock',
                                style: AppText.caption.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 6b. Info Overlay
                  if (!_appMode.isTv && !_locked && _infoPanelOpen && _infoFields.isNotEmpty)
                    Positioned(
                      left: 16,
                      top: MediaQuery.paddingOf(context).top + 58,
                      child: IgnorePointer(
                        child: _InfoOverlay(controller: _c, fields: _infoFields),
                      ),
                    ),

                  // 6b-iii. Flash Feedback
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _flashing ? 0.85 : 0,
                        duration: const Duration(milliseconds: 110),
                        child: const ColoredBox(color: Colors.white),
                      ),
                    ),
                  ),

                  // 6c. AniSkip Button
                  if (!_locked && !_upNext && !_appMode.isTv)
                    StreamBuilder<Duration>(
                      stream: _positionBySecond,
                      builder: (context, snap) {
                        final btn = _skipButtonFor(snap.data ?? Duration.zero);
                        if (btn == null) return const SizedBox.shrink();
                        return AnimatedAlign(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          alignment: Alignment(0.94, _controlsVisible ? 0.4 : 0.74),
                          child: btn,
                        );
                      },
                    ),

                  // 6c-iii. MegaSkip Flash Pill
                  if (_megaFlash)
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.keyboard_double_arrow_right_rounded, color: Colors.white, size: 22),
                              const SizedBox(width: 6),
                              Text(
                                '+${_megaSkipSeconds}s',
                                style: AppText.headline.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 6d. Outro Next Pill
                  if (!_locked && !_upNext && !_controlsVisible) _buildOutroNextButton(),

                  // 7. Up Next Card
                  if (_upNext) _buildUpNextCard(),

                  // 8. In-Room Chat Panel
                  if (_room.room != null && _chatOpen)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: SafeArea(
                        left: false,
                        right: false,
                        child: RoomChatPanel(
                          controller: _room,
                          onClose: () => setState(() => _chatOpen = false),
                        ),
                      ),
                    ),

                  // 9. Cast Remote Panel
                  AnimatedBuilder(
                    animation: _castController,
                    builder: (context, _) {
                      if (_castController.state != CastState.connected) {
                        return const SizedBox.shrink();
                      }
                      return Positioned.fill(
                        child: _CastRemotePanel(
                          deviceName: _castController.deviceName ?? 'TV',
                          showTitle: widget.showTitle,
                          cover: widget.cover,
                          loadError: _castController.loadError,
                          onBack: () => Navigator.of(context).maybePop(),
                          onStop: () => _castController.stop(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    if (_appMode.isTv) {
      return PopScope(
        canPop: !_tvBarVisible,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _tvBarVisible) setState(() => _tvBarVisible = false);
        },
        child: scaffold,
      );
    }

    return PopScope(
      canPop: _prefs.closeConfirmation == 'direct',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleCloseRequest();
      },
      child: scaffold,
    );
  }
}
