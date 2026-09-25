import 'package:flutter/foundation.dart';

import 'stremio_client.dart';
import 'stremio_manifest.dart';
import 'stremio_provider.dart';
import 'stremio_store.dart';

class StremioManager extends ChangeNotifier {
  StremioManager({
    required StremioStore store,
    required StremioClient client,
  })  : _store = store,
        _client = client {
    _syncProviders();
    _store.addListener(_onStoreChanged);
  }

  final StremioStore _store;
  final StremioClient _client;
  final Map<String, StremioProvider> _providers = {};

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    _syncProviders();
    notifyListeners();
  }

  void _syncProviders() {
    _providers.clear();
    for (final entry in _store.enabled()) {
      final p = StremioProvider(entry: entry, client: _client);
      _providers[p.sourceId] = p;
    }
  }

  List<StremioProvider> get providers => _providers.values.toList();
  List<StremioAddonEntry> get allAddons => _store.all();

  StremioProvider? getProvider(String sourceId) {
    if (!sourceId.startsWith('stremio:')) return null;
    return _providers[sourceId];
  }

  bool hasProvider(String sourceId) => _providers.containsKey(sourceId);

  /// Installs or updates a Stremio addon from its manifest URL.
  Future<StremioAddonEntry> installAddon(String manifestUrl) async {
    final canonUrl = StremioClient.canonicalizeManifestUrl(manifestUrl);
    final manifest = await _client.getManifest(canonUrl);
    final entry = StremioAddonEntry(
      manifestUrl: canonUrl,
      manifest: manifest,
      enabled: true,
      installedAt: DateTime.now(),
    );
    await _store.save(entry);
    return entry;
  }

  Future<void> uninstallAddon(String manifestUrl) async {
    final canonUrl = StremioClient.canonicalizeManifestUrl(manifestUrl);
    await _store.delete(canonUrl);
  }

  Future<void> toggleAddon(String manifestUrl, bool enabled) async {
    final canonUrl = StremioClient.canonicalizeManifestUrl(manifestUrl);
    await _store.setEnabled(canonUrl, enabled);
  }
}
