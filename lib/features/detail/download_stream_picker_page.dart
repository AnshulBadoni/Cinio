part of 'detail_screen.dart';

class _ProviderTab {
  final String id;
  final String name;
  final bool isAll;
  final bool isStremio;
  final StremioProvider? stremioProvider;

  const _ProviderTab({
    required this.id,
    required this.name,
    this.isAll = false,
    this.isStremio = false,
    this.stremioProvider,
  });
}

class _StreamParsedInfo {
  final String providerName;
  final String qualityBadge;
  final String releaseTitle;
  final String? seeders;
  final String? size;
  final String? tracker;
  final String? flagsOrAudio;

  const _StreamParsedInfo({
    required this.providerName,
    required this.qualityBadge,
    required this.releaseTitle,
    this.seeders,
    this.size,
    this.tracker,
    this.flagsOrAudio,
  });
}

class _StreamEntry {
  final VideoSource source;
  final _StreamParsedInfo info;
  final MediaItem? resolvedItem;
  final MediaDetail? resolvedDetail;
  final Episode? resolvedEpisode;

  const _StreamEntry({
    required this.source,
    required this.info,
    this.resolvedItem,
    this.resolvedDetail,
    this.resolvedEpisode,
  });
}

class DownloadStreamPickerPage extends StatefulWidget {
  const DownloadStreamPickerPage({
    super.key,
    required this.item,
    required this.detail,
    required this.episode,
    required this.category,
    this.titleLogoUrl,
  });

  final MediaItem item;
  final MediaDetail detail;
  final Episode episode;
  final String category;
  final String? titleLogoUrl;

  @override
  State<DownloadStreamPickerPage> createState() =>
      _DownloadStreamPickerPageState();
}

class _DownloadStreamPickerPageState extends State<DownloadStreamPickerPage> {
  final List<_ProviderTab> _tabs = [];
  int _selectedTabIndex = 0;
  final Map<String, List<_StreamEntry>> _cache = {};
  bool _loading = false;
  String? _error;
  int _activeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _initTabs();
    _loadCurrentTab();
  }

  void _initTabs() {
    _tabs.clear();

    final isTpdb = widget.item.sourceId.startsWith('tpdb:');
    final primaryPref = isTpdb
        ? sl<PlaybackPrefs>().tpdbPrimaryProvider
        : sl<PlaybackPrefs>().tmdbPrimaryProvider;
    final selectedSourceId = primaryPref.isNotEmpty
        ? primaryPref
        : (widget.detail.sourceId != 'tmdb:catalog' &&
                !widget.detail.sourceId.startsWith('tpdb:'))
            ? widget.detail.sourceId
            : sl<SourceRepository>().sourceId;

    final allProviderTabs = <_ProviderTab>[];

    // 1. Stremio providers
    final stremioProviders = sl<StremioManager>().providers;
    for (final p in stremioProviders) {
      allProviderTabs.add(
        _ProviderTab(
          id: p.sourceId,
          name: p.displayName,
          isStremio: true,
          stremioProvider: p,
        ),
      );
    }

    // 2. Non-Stremio sources
    final loadedSources = sl<SourceRepository>().loadedSources;
    for (final s in loadedSources) {
      if (s.id == 'tmdb:catalog' ||
          s.id.startsWith('tpdb:') ||
          s.id.startsWith('stremio:')) {
        continue;
      }
      allProviderTabs.add(
        _ProviderTab(
          id: s.id,
          name: s.name,
          isStremio: false,
        ),
      );
    }

    // 3. Put selected provider first as requested
    _ProviderTab? selectedTab;
    final otherTabs = <_ProviderTab>[];

    for (final tab in allProviderTabs) {
      final isMatch = tab.id == selectedSourceId ||
          tab.id.toLowerCase() == selectedSourceId.toLowerCase() ||
          tab.name.toLowerCase() == selectedSourceId.toLowerCase() ||
          (selectedSourceId.toLowerCase().contains('torrentio') &&
              tab.name.toLowerCase().contains('torrentio'));

      if (isMatch && selectedTab == null) {
        selectedTab = tab;
      } else {
        otherTabs.add(tab);
      }
    }

    if (selectedTab != null) {
      _tabs.add(selectedTab);
    }
    _tabs.addAll(otherTabs);

    // If no installed providers were found, fallback
    if (_tabs.isEmpty) {
      _tabs.add(
        const _ProviderTab(
          id: 'default',
          name: 'Torrentio',
          isStremio: false,
        ),
      );
    }

    // Append "All" tab at the end
    _tabs.add(const _ProviderTab(id: 'all', name: 'All', isAll: true));

    _selectedTabIndex = 0;
  }

  Future<void> _loadCurrentTab() async {
    if (_tabs.isEmpty) return;
    final currentTab = _tabs[_selectedTabIndex];

    if (_cache.containsKey(currentTab.id)) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }

    final reqId = ++_activeRequestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await _fetchForTab(currentTab);
      if (!mounted || reqId != _activeRequestId) return;
      _cache[currentTab.id] = results;
      setState(() {
        _loading = false;
        if (results.isEmpty) {
          _error = 'No streams found on ${currentTab.name}';
        }
      });
    } catch (e) {
      if (!mounted || reqId != _activeRequestId) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load streams: $e';
      });
    }
  }

  Future<List<_StreamEntry>> _fetchForTab(_ProviderTab tab) async {
    if (tab.isAll) {
      final nonAll = _tabs.where((t) => !t.isAll).toList();
      final futures = nonAll.map((t) async {
        if (_cache.containsKey(t.id)) return _cache[t.id]!;
        try {
          final res = await _fetchSingleProvider(t);
          _cache[t.id] = res;
          return res;
        } catch (_) {
          return <_StreamEntry>[];
        }
      });
      final nested = await Future.wait(futures);
      return nested.expand((x) => x).toList();
    }
    return await _fetchSingleProvider(tab);
  }

  Future<List<_StreamEntry>> _fetchSingleProvider(_ProviderTab tab) async {
    final entries = <_StreamEntry>[];

    if (tab.isStremio && tab.stremioProvider != null) {
      final p = tab.stremioProvider!;
      String? imdbId = widget.detail.imdbId ?? widget.item.imdbId;
      if (imdbId == null || imdbId.isEmpty) {
        imdbId =
            await sl<SourceRepository>().resolveImdbForCatalog(widget.item);
      }

      final isTv = widget.detail.isSeries ||
          widget.item.tmdbIsTv ||
          widget.episode.season != null;
      final season = seasonOf(widget.episode) ?? 1;
      final epNum = widget.episode.number?.toInt() ?? 1;

      String targetId = '';
      String streamType = isTv ? 'series' : 'movie';

      if (imdbId != null && imdbId.isNotEmpty) {
        targetId = isTv ? '$imdbId:$season:$epNum' : imdbId;
      } else if (widget.episode.url.startsWith('stremio://')) {
        final uri = Uri.tryParse(widget.episode.url);
        if (uri != null && uri.pathSegments.length >= 3) {
          streamType = uri.pathSegments[1];
          targetId = uri.pathSegments.sublist(2).join('/');
        }
      }

      if (targetId.isNotEmpty) {
        final rawStreams = await p.client
            .getStreams(
              baseUrl: p.baseUrl,
              type: streamType,
              id: targetId,
            )
            .timeout(
              const Duration(seconds: 14),
              onTimeout: () => <StremioStream>[],
            );

        for (final s in rawStreams) {
          final vs = s.toVideoSource(addonName: p.displayName);
          if (vs != null) {
            final info = _parseStreamInfo(
              defaultProviderName: p.displayName,
              rawName: s.name,
              rawTitle: s.title ?? s.description,
              rawQuality: vs.quality,
              videoSource: vs,
            );
            entries.add(_StreamEntry(source: vs, info: info));
          }
        }
      }
    } else {
      final repo = sl<SourceRepository>();
      final isCatalog = widget.item.sourceId == 'tmdb:catalog' ||
          widget.item.sourceId.startsWith('tpdb:');

      String epUrl = widget.episode.url;
      var resolvedDetail = widget.detail;
      var resolvedItem = widget.item;
      var resolvedEp = widget.episode;

      if (isCatalog) {
        final hit = await repo
            .resolveCatalogTitle(
              widget.item,
              category: widget.category,
              sourceIdOverride: tab.id,
            )
            .timeout(const Duration(seconds: 10), onTimeout: () => null);

        if (hit != null) {
          resolvedItem = hit.item;
          resolvedDetail = hit.detail;
          resolvedEp =
              _matchTargetEpisode(hit.detail, hit.item, widget.episode);
          epUrl = resolvedEp.url;
        } else {
          return [];
        }
      }

      var sources = await repo
          .sources(epUrl, sourceId: tab.id, fast: true)
          .timeout(const Duration(seconds: 10), onTimeout: () => <VideoSource>[]);

      final isCloudStream =
          tab.id.startsWith('cs:') || tab.id.startsWith('cloudstream:');
      if (isCloudStream) {
        var pollTries = 0;
        var done = false;
        final knownUrls = sources.map((s) => s.url).toSet();
        while (!done && pollTries < 3) {
          await Future.delayed(const Duration(milliseconds: 600));
          pollTries++;
          final polled = await repo.polledSources(epUrl, sourceId: tab.id);
          done = polled.done;
          final newOnes =
              polled.sources.where((e) => !knownUrls.contains(e.url)).toList();
          if (newOnes.isNotEmpty) {
            for (final n in newOnes) {
              knownUrls.add(n.url);
            }
            sources = [...sources, ...newOnes];
          }
        }
      }

      for (var i = 0; i < sources.length; i++) {
        final vs = sources[i];
        final info = _parseStreamInfo(
          defaultProviderName: tab.name,
          rawQuality: vs.quality,
          videoSource: vs,
          fallbackTitle: vs.label ?? 'Server ${i + 1}',
        );
        entries.add(
          _StreamEntry(
            source: vs,
            info: info,
            resolvedItem: resolvedItem,
            resolvedDetail: resolvedDetail,
            resolvedEpisode: resolvedEp,
          ),
        );
      }
    }

    return entries;
  }

  _StreamParsedInfo _parseStreamInfo({
    required String defaultProviderName,
    String? rawName,
    String? rawTitle,
    String? rawQuality,
    VideoSource? videoSource,
    String? fallbackTitle,
  }) {
    String providerName = defaultProviderName;
    String qualityBadge = rawQuality ?? 'Auto';
    String releaseTitle = fallbackTitle ?? '';
    String? seeders;
    String? size;
    String? tracker;
    String? flagsOrAudio;

    if (rawName != null && rawName.trim().isNotEmpty) {
      final lines = rawName
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        providerName = lines[0];
      }
      if (lines.length > 1) {
        qualityBadge = lines.sublist(1).join(' | ');
      }
    }

    if (rawTitle != null && rawTitle.trim().isNotEmpty) {
      final lines = rawTitle
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final titleParts = <String>[];

      final seederRegex = RegExp(
        r'(?:👤|🌱)\s*(\d+)|\b(\d+)\s*(?:seeders?|seeds?)\b',
        caseSensitive: false,
      );
      final sizeRegex = RegExp(
        r'(?:💾|📦)?\s*(\d+(?:\.\d+)?\s*(?:GB|MB|GiB|MiB|KB|KiB))\b',
        caseSensitive: false,
      );
      final trackerRegex = RegExp(r'(?:⚙️|⚙)\s*([A-Za-z0-9_.\-]+)');
      final flagOrAudioRegex = RegExp(
        r'[\u{1F1E6}-\u{1F1FF}]|Dual Audio|Multi|Dub|Sub',
        unicode: true,
        caseSensitive: false,
      );

      for (final line in lines) {
        final isStats = line.contains('👤') ||
            line.contains('💾') ||
            line.contains('⚙') ||
            line.toLowerCase().contains('seeders');

        if (isStats) {
          final sm = seederRegex.firstMatch(line);
          if (sm != null) seeders = sm.group(1) ?? sm.group(2);
          final szm = sizeRegex.firstMatch(line);
          if (szm != null) size = szm.group(1);
          final tm = trackerRegex.firstMatch(line);
          if (tm != null) tracker = tm.group(1);
        } else if (flagOrAudioRegex.hasMatch(line) ||
            line.contains('🇬🇧') ||
            line.contains('🇷🇺') ||
            line.contains('🇮🇳') ||
            line.contains('🇨🇿')) {
          flagsOrAudio = line;
        } else {
          titleParts.add(line);
        }
      }

      if (titleParts.isNotEmpty) {
        releaseTitle = titleParts.join(' ');
      }
    }

    if (releaseTitle.isEmpty) {
      releaseTitle = videoSource?.label ?? '';
    }
    if (qualityBadge == 'Auto' && videoSource?.quality != null) {
      qualityBadge = videoSource!.quality!;
    }

    return _StreamParsedInfo(
      providerName: providerName,
      qualityBadge: qualityBadge,
      releaseTitle: releaseTitle,
      seeders: seeders,
      size: size,
      tracker: tracker,
      flagsOrAudio: flagsOrAudio,
    );
  }

  void _onTabSelected(int index) {
    if (index == _selectedTabIndex && !_loading) return;
    setState(() => _selectedTabIndex = index);
    _loadCurrentTab();
  }

  void _onRefresh() {
    if (_tabs.isEmpty) return;
    final currentTab = _tabs[_selectedTabIndex];
    _cache.remove(currentTab.id);
    _loadCurrentTab();
  }

  void _selectStream(_StreamEntry entry) {
    final targetItem = entry.resolvedItem ?? widget.item;
    final targetDetail = entry.resolvedDetail ?? widget.detail;
    final targetEp = entry.resolvedEpisode ?? widget.episode;

    final allSources = (_cache[_tabs[_selectedTabIndex].id] ?? [])
        .map((e) => e.source)
        .toList();

    Navigator.of(context).pop((
      chosen: entry.source,
      all: allSources,
      resolvedItem: targetItem,
      resolvedDetail: targetDetail,
      resolvedEpisode: targetEp,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs.isNotEmpty ? _tabs[_selectedTabIndex] : null;
    final streams = currentTab != null ? (_cache[currentTab.id] ?? []) : <_StreamEntry>[];

    return Scaffold(
      backgroundColor: const Color(0xFF070709),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top App Bar: Back button + Title logo / name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Center(
                        child: (widget.titleLogoUrl != null &&
                                widget.titleLogoUrl!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: widget.titleLogoUrl!,
                                height: 44,
                                fit: BoxFit.contain,
                                errorWidget: (_, __, ___) => _titleTextFallback(),
                              )
                            : _titleTextFallback(),
                      ),
                    ),
                    const SizedBox(width: 48), // Balancing width for back icon
                  ],
                ),
              ),
            ),

            // Horizontal Pill Tabs Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Refresh button pill
                  InkWell(
                    onTap: _onRefresh,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 48,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B1F),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  // Provider Tabs
                  for (var i = 0; i < _tabs.length; i++) ...[
                    const SizedBox(width: 8),
                    _buildPillTab(_tabs[i], isSelected: i == _selectedTabIndex, onTap: () => _onTabSelected(i)),
                  ],
                ],
              ),
            ),

            // Section Header
            if (currentTab != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  currentTab.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // Content: Loading, Error, or Streams List
            Expanded(
              child: _buildContent(streams),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleTextFallback() {
    final title = widget.detail.title.trim().isNotEmpty
        ? widget.detail.title
        : widget.item.title;
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPillTab(_ProviderTab tab, {required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2172ED) : const Color(0xFF1B1B1F),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          tab.name,
          style: TextStyle(
            color: Colors.white.withValues(alpha: isSelected ? 1.0 : 0.85),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<_StreamEntry> streams) {
    if (_loading && streams.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF2172ED),
          strokeWidth: 2.8,
        ),
      );
    }

    if (_error != null && streams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 44),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (streams.isEmpty) {
      return const Center(
        child: Text(
          'No streams available for this provider',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      itemCount: streams.length,
      itemBuilder: (context, index) {
        final entry = streams[index];
        return _buildStreamCard(entry);
      },
    );
  }

  Widget _buildStreamCard(_StreamEntry entry) {
    final info = entry.info;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131316),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectStream(entry),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Line 1: Provider Name
                Text(
                  info.providerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),

                // Line 2: Quality Badge(s)
                Text(
                  info.qualityBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),

                // Line 3: Release Title / Filename
                if (info.releaseTitle.isNotEmpty) ...[
                  Text(
                    info.releaseTitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                ],

                // Line 4: Stats Row (Seeders, Size, Tracker)
                if (info.seeders != null || info.size != null || info.tracker != null)
                  Row(
                    children: [
                      if (info.seeders != null) ...[
                        const Icon(Icons.person, size: 14, color: Color(0xFF2F80ED)),
                        const SizedBox(width: 4),
                        Text(
                          info.seeders!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (info.size != null) ...[
                        const Icon(Icons.save_rounded, size: 14, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          info.size!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (info.tracker != null) ...[
                        const Icon(Icons.settings, size: 14, color: Color(0xFF56CCF2)),
                        const SizedBox(width: 4),
                        Text(
                          info.tracker!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),

                // Line 5: Flags / Audio
                if (info.flagsOrAudio != null && info.flagsOrAudio!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    info.flagsOrAudio!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
