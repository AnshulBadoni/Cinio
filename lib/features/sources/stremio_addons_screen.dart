import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../core/stremio/stremio_client.dart';
import '../../core/stremio/stremio_manager.dart';
import '../../core/stremio/stremio_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

class StremioAddonsScreen extends StatefulWidget {
  const StremioAddonsScreen({super.key});

  @override
  State<StremioAddonsScreen> createState() => _StremioAddonsScreenState();
}

class _StremioAddonsScreenState extends State<StremioAddonsScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  static const List<({String name, String description, String url, IconData icon})> _popularAddons = [
    (
      name: 'Torrentio (Streams)',
      description: 'Scrapes torrents & Debrid streams (RD/AD/PM) for movies and series',
      url: 'https://torrentio.strem.fun/manifest.json',
      icon: CupertinoIcons.play_circle_fill,
    ),
    (
      name: 'MediaFusion (Streams & Live)',
      description: 'Multi-source streamer with Debrid support and live content',
      url: 'https://mediafusion.elfhosted.com/manifest.json',
      icon: CupertinoIcons.film_fill,
    ),
    (
      name: 'Comet (Debrid Streamer)',
      description: 'Fast Stremio addon for cached Real-Debrid / AllDebrid streams',
      url: 'https://comet.elfhosted.com/manifest.json',
      icon: CupertinoIcons.sparkles,
    ),
    (
      name: 'OpenSubtitles v3',
      description: 'Official multi-language subtitle streams for movies and TV shows',
      url: 'https://opensubtitles-v3.strem.fun/manifest.json',
      icon: CupertinoIcons.captions_bubble_fill,
    ),
    (
      name: 'Anime Kitsu',
      description: 'Anime catalog & metadata powered by Kitsu.io',
      url: 'https://anime-kitsu.strem.fun/manifest.json',
      icon: CupertinoIcons.tv,
    ),
    (
      name: 'CyberFlix Catalog',
      description: 'Curated Netflix, Disney+, Apple TV+, HBO Max catalogs',
      url: 'https://cyberflix.elfhosted.com/manifest.json',
      icon: CupertinoIcons.square_grid_2x2_fill,
    ),
  ];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _installFromInput([String? presetUrl]) async {
    final raw = presetUrl ?? _urlController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final manager = sl<StremioManager>();
      final entry = await manager.installAddon(raw);
      if (mounted) {
        _urlController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Installed “${entry.manifest.name}”'),
            backgroundColor: AppColors.surface2,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load manifest: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      _urlController.text = data!.text!.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Stremio Addons', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: sl<StremioManager>(),
        builder: (context, _) {
          final installed = sl<StremioManager>().allAddons;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildAddSection(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildSectionHeader('INSTALLED ADDONS', count: installed.length),
              const SizedBox(height: 8),
              if (installed.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'No Stremio addons installed yet.\nPaste a manifest URL or select a preset below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textTertiary, height: 1.5),
                    ),
                  ),
                )
              else
                ...installed.map((entry) => _buildAddonTile(entry)),
              const SizedBox(height: 32),
              _buildSectionHeader('POPULAR ADDONS'),
              const SizedBox(height: 8),
              ..._popularAddons.map((preset) => _buildPresetTile(preset, installed)),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAddSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B5BF2).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(CupertinoIcons.link, color: Color(0xFF9D84F7), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Install Stremio Addon',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Paste any manifest URL (e.g. Torrentio, Comet, Debrid)',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'https://.../manifest.json',
                    hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.surface2,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18, color: AppColors.textSecondary),
                      onPressed: _pasteFromClipboard,
                      tooltip: 'Paste from clipboard',
                    ),
                  ),
                  onSubmitted: (_) => _installFromInput(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _loading ? null : () => _installFromInput(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7B5BF2),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Install', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {int? count}) {
    return Row(
      children: [
        Text(
          title,
          style: AppText.overline.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: AppText.overline.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _buildAddonTile(StremioAddonEntry entry) {
    final manifest = entry.manifest;
    final badges = <String>[
      if (manifest.supportsStreams) 'Streams',
      if (manifest.supportsCatalogs) 'Catalogs',
      if (manifest.supportsSubtitles) 'Subtitles',
      if (manifest.isP2p) 'P2P',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surface2),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF7B5BF2).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: manifest.logo != null && manifest.logo!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    manifest.logo!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      CupertinoIcons.cube_box_fill,
                      color: Color(0xFF9D84F7),
                    ),
                  ),
                )
              : const Icon(CupertinoIcons.cube_box_fill, color: Color(0xFF9D84F7)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                manifest.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'v${manifest.version}',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (manifest.description != null && manifest.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                manifest.description!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: badges.map((badge) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B5BF2).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Color(0xFFB5A4FA),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoSwitch(
              value: entry.enabled,
              activeTrackColor: const Color(0xFF7B5BF2),
              onChanged: (val) => sl<StremioManager>().toggleAddon(entry.manifestUrl, val),
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.trash, color: AppColors.textTertiary, size: 19),
              onPressed: () => _confirmDelete(entry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetTile(
    ({String name, String description, String url, IconData icon}) preset,
    List<StremioAddonEntry> installed,
  ) {
    final canon = StremioClient.canonicalizeManifestUrl(preset.url);
    final isInstalled = installed.any((e) => e.manifestUrl == canon);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surface2),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isInstalled
                ? Colors.green.withValues(alpha: 0.15)
                : AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            preset.icon,
            color: isInstalled ? Colors.greenAccent : AppColors.textSecondary,
            size: 20,
          ),
        ),
        title: Text(
          preset.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          preset.description,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        trailing: isInstalled
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Installed',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              )
            : OutlinedButton(
                onPressed: _loading ? null : () => _installFromInput(preset.url),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF7B5BF2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(color: Color(0xFF9D84F7), fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
      ),
    );
  }

  Future<void> _confirmDelete(StremioAddonEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove “${entry.manifest.name}”?'),
        content: const Text('This will remove the addon and its streaming links.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      await sl<StremioManager>().uninstallAddon(entry.manifestUrl);
    }
  }
}
