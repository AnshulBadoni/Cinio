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

  List<_ProviderTab> _buildAllCandidateTabs(bool isTpdb) {
    final tabs = <_ProviderTab>[];
    final addedIds = <String>{};

    // 1. Stremio providers
    final stremioProviders = sl<StremioManager>().providers;
    for (final p in stremioProviders) {
      if (!addedIds.contains(p.sourceId)) {
        addedIds.add(p.sourceId);
        tabs.add(
          _ProviderTab(
            id: p.sourceId,
            name: p.displayName,
            isStremio: true,
            stremioProvider: p,
          ),
        );
      }
    }

    // 2. Non-Stremio sources from SourceRepository
    final repo = sl<SourceRepository>();
    final loadedSources = repo.loadedSources;
    for (final s in loadedSources) {
      if (s.id == 'tmdb:catalog' ||
          s.id.startsWith('tpdb:') ||
          s.id.startsWith('stremio:')) {
        continue;
      }
      if (!addedIds.contains(s.id)) {
        addedIds.add(s.id);
        tabs.add(
          _ProviderTab(
            id: s.id,
            name: s.name,
            isStremio: false,
          ),
        );
      }
    }

    return tabs;
  }

  void _initTabs() {
    _tabs.clear();

    final isTpdb = widget.item.sourceId.startsWith('tpdb:');
    final repo = sl<SourceRepository>();
    final downloadPrefs = sl<DownloadPrefs>();
    final playbackPrefs = sl<PlaybackPrefs>();

    final primaryPref = isTpdb
        ? playbackPrefs.tpdbPrimaryProvider
        : playbackPrefs.tmdbPrimaryProvider;

    final candidates = _buildAllCandidateTabs(isTpdb);

    final savedOrder = isTpdb
        ? downloadPrefs.tpdbDownloadSourceOrder
        : downloadPrefs.tmdbDownloadSourceOrder;
    final disabledSources = isTpdb
        ? downloadPrefs.tpdbDisabledDownloadSources
        : downloadPrefs.tmdbDisabledDownloadSources;

    // Filter out disabled sources
    candidates.removeWhere((t) => disabledSources.contains(t.id));

    if (savedOrder.isNotEmpty) {
      candidates.sort((a, b) {
        final aIdx = savedOrder.indexOf(a.id);
        final bIdx = savedOrder.indexOf(b.id);
        final aRank = aIdx != -1 ? aIdx : 9999;
        final bRank = bIdx != -1 ? bIdx : 9999;
        return aRank.compareTo(bRank);
      });
    } else {
      candidates.sort((a, b) {
        int score(_ProviderTab tab) {
          final idLower = tab.id.toLowerCase();
          final nameLower = tab.name.toLowerCase();

          // Explicit primary provider preference comes first
          if (primaryPref.isNotEmpty &&
              (tab.id == primaryPref || idLower == primaryPref.toLowerCase())) {
            return -100;
          }

          if (isTpdb) {
            // Himeros first for TPDB
            if (idLower.contains('himeros') || nameLower.contains('himeros')) {
              return -90;
            }
            // Other adult sources next
            if (repo.isAdultSource(tab.id)) {
              return -50;
            }
            return 10;
          } else {
            // Torrentio first for TMDB
            if (idLower.contains('torrentio') || nameLower.contains('torrentio')) {
              return -90;
            }
            // Other Stremio providers next
            if (tab.isStremio) {
              return -50;
            }
            return 10;
          }
        }

        final diff = score(a).compareTo(score(b));
        if (diff != 0) return diff;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    _tabs.addAll(candidates);

    if (_tabs.isEmpty) {
      _tabs.add(
        const _ProviderTab(
          id: 'default',
          name: 'Torrentio',
          isStremio: false,
        ),
      );
    }

    // Prepend "All" tab at the very beginning
    _tabs.insert(0, const _ProviderTab(id: 'all', name: 'All', isAll: true));

    // Determine default selected tab
    final defaultTabChoice = downloadPrefs.defaultDownloadSourceTab;
    if (defaultTabChoice == 'first_source' && _tabs.length > 1) {
      _selectedTabIndex = 1;
    } else {
      _selectedTabIndex = 0;
    }
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

  Future<void> _openReorderSheet() async {
    final downloadPrefs = sl<DownloadPrefs>();
    final isTpdb = widget.item.sourceId.startsWith('tpdb:');

    final candidates = _buildAllCandidateTabs(isTpdb);
    final savedOrder = isTpdb
        ? downloadPrefs.tpdbDownloadSourceOrder
        : downloadPrefs.tmdbDownloadSourceOrder;
    final disabledSet = isTpdb
        ? Set<String>.from(downloadPrefs.tpdbDisabledDownloadSources)
        : Set<String>.from(downloadPrefs.tmdbDisabledDownloadSources);

    if (savedOrder.isNotEmpty) {
      candidates.sort((a, b) {
        final aIdx = savedOrder.indexOf(a.id);
        final bIdx = savedOrder.indexOf(b.id);
        final aRank = aIdx != -1 ? aIdx : 9999;
        final bRank = bIdx != -1 ? bIdx : 9999;
        return aRank.compareTo(bRank);
      });
    } else {
      final repo = sl<SourceRepository>();
      final primaryPref = isTpdb
          ? sl<PlaybackPrefs>().tpdbPrimaryProvider
          : sl<PlaybackPrefs>().tmdbPrimaryProvider;
      candidates.sort((a, b) {
        int score(_ProviderTab tab) {
          final idLower = tab.id.toLowerCase();
          final nameLower = tab.name.toLowerCase();
          if (primaryPref.isNotEmpty &&
              (tab.id == primaryPref || idLower == primaryPref.toLowerCase())) {
            return -100;
          }
          if (isTpdb) {
            if (idLower.contains('himeros') || nameLower.contains('himeros')) {
              return -90;
            }
            if (repo.isAdultSource(tab.id)) return -50;
            return 10;
          } else {
            if (idLower.contains('torrentio') || nameLower.contains('torrentio')) {
              return -90;
            }
            if (tab.isStremio) return -50;
            return 10;
          }
        }

        final diff = score(a).compareTo(score(b));
        if (diff != 0) return diff;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    String defaultTab = downloadPrefs.defaultDownloadSourceTab;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141418),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final firstSourceName =
                candidates.isNotEmpty ? candidates.first.name : 'First source';
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isTpdb
                          ? 'TPDB Download Sources Order'
                          : 'TMDB Download Sources Order',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Drag to order sources shown after "All". Choose which tab opens by default.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Default Selected Tab',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    setSheetState(() => defaultTab = 'all');
                                    await downloadPrefs.setDefaultDownloadSourceTab('all');
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: defaultTab == 'all'
                                          ? const Color(0xFF38BDF8).withValues(alpha: 0.20)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: defaultTab == 'all'
                                            ? const Color(0xFF38BDF8)
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'All',
                                        style: TextStyle(
                                          color: defaultTab == 'all'
                                              ? const Color(0xFF38BDF8)
                                              : Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    setSheetState(() => defaultTab = 'first_source');
                                    await downloadPrefs.setDefaultDownloadSourceTab('first_source');
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: defaultTab == 'first_source'
                                          ? const Color(0xFF38BDF8).withValues(alpha: 0.20)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: defaultTab == 'first_source'
                                            ? const Color(0xFF38BDF8)
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Second Tab ($firstSourceName)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: defaultTab == 'first_source'
                                              ? const Color(0xFF38BDF8)
                                              : Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                      ),
                      child: candidates.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text('No sources available',
                                    style: TextStyle(color: Colors.white54)),
                              ),
                            )
                          : ReorderableListView.builder(
                              shrinkWrap: true,
                              itemCount: candidates.length,
                              onReorder: (oldIndex, newIndex) async {
                                setSheetState(() {
                                  if (newIndex > oldIndex) newIndex--;
                                  final item = candidates.removeAt(oldIndex);
                                  candidates.insert(newIndex, item);
                                });
                                final newOrder =
                                    candidates.map((e) => e.id).toList();
                                if (isTpdb) {
                                  await downloadPrefs
                                      .setTpdbDownloadSourceOrder(newOrder);
                                } else {
                                  await downloadPrefs
                                      .setTmdbDownloadSourceOrder(newOrder);
                                }
                              },
                              itemBuilder: (context, idx) {
                                final s = candidates[idx];
                                final isHidden = disabledSet.contains(s.id);
                                return ListTile(
                                  key: ValueKey(s.id),
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${idx + 1}',
                                      style: TextStyle(
                                        color: isHidden
                                            ? Colors.white38
                                            : Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    s.name,
                                    style: TextStyle(
                                      color: isHidden
                                          ? Colors.white38
                                          : Colors.white,
                                      decoration: isHidden
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isHidden
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: isHidden
                                              ? Colors.white38
                                              : const Color(0xFF38BDF8),
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          setSheetState(() {
                                            if (isHidden) {
                                              disabledSet.remove(s.id);
                                            } else {
                                              disabledSet.add(s.id);
                                            }
                                          });
                                          if (isTpdb) {
                                            await downloadPrefs
                                                .setTpdbDisabledDownloadSources(
                                                    disabledSet);
                                          } else {
                                            await downloadPrefs
                                                .setTmdbDisabledDownloadSources(
                                                    disabledSet);
                                          }
                                        },
                                      ),
                                      ReorderableDragStartListener(
                                        index: idx,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Icon(Icons.drag_handle_rounded,
                                              color: Colors.white38),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      setState(() {
        _initTabs();
        _loadCurrentTab();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs.isNotEmpty ? _tabs[_selectedTabIndex] : null;
    final streams = currentTab != null ? (_cache[currentTab.id] ?? []) : <_StreamEntry>[];

    return Scaffold(
      backgroundColor: const Color(0xFF070709),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header: Episode / Movie Full Head Image edge-to-edge
          _buildHeader(context),

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
                    width: 44,
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
                const SizedBox(width: 8),

                // Reorder sources & default tab settings pill
                InkWell(
                  onTap: _openReorderSheet,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 44,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B1F),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                        size: 19,
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final headerHeight = 210.0 + topPadding;

    final epThumb = widget.episode.thumbnail?.trim();
    final detailCover = widget.detail.cover?.trim();
    final itemCover = widget.item.cover?.trim();

    final imageUrl = (epThumb != null && epThumb.isNotEmpty)
        ? epThumb
        : (detailCover != null && detailCover.isNotEmpty)
            ? detailCover
            : itemCover;

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    final ep = widget.episode;
    final epNum = ep.number != null
        ? (ep.number! == ep.number!.toInt() ? ep.number!.toInt() : ep.number!)
        : null;
    final seasonNum = ep.season ?? seasonOf(ep);
    final epTag = (seasonNum != null && epNum != null)
        ? 'S$seasonNum E$epNum'
        : (epNum != null
            ? 'E$epNum'
            : (widget.item.tmdbIsTv ? 'Episode' : 'Movie'));

    final epTitle = episodeDisplayTitle(ep) ??
        (ep.title.trim().isNotEmpty ? ep.title.trim() : null);
    final showTitle = widget.detail.title.trim().isNotEmpty
        ? widget.detail.title.trim()
        : widget.item.title.trim();

    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Edge-to-edge full head image
          if (hasImage)
            Image(
              image: nativeCoverProvider(
                imageUrl,
                widget.item.coverHeaders,
                showUrl: widget.item.url,
                sourceId: widget.item.sourceId,
              ),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFF131316),
                child: const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.white24,
                    size: 36,
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A1A24),
                    Color(0xFF0F0F14),
                  ],
                ),
              ),
            ),

          // Cinematic vignette and bottom fade into background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.20),
                    Colors.black.withValues(alpha: 0.60),
                    const Color(0xFF070709),
                  ],
                  stops: const [0.0, 0.35, 0.70, 1.0],
                ),
              ),
            ),
          ),

          // Back button in safe area
          Positioned(
            top: topPadding + 6,
            left: 12,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.50),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),

          // Episode / Movie title & metadata overlay at bottom
          Positioned(
            left: 16,
            right: 16,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (epTag.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.50),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      epTag,
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (epTitle != null) ...[
                  Text(
                    epTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  showTitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
        top: 4,
      ),
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
