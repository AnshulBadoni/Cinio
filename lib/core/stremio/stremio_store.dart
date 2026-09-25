import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'stremio_manifest.dart';

class StremioAddonEntry extends Equatable {
  final String manifestUrl;
  final StremioManifest manifest;
  final bool enabled;
  final DateTime installedAt;

  const StremioAddonEntry({
    required this.manifestUrl,
    required this.manifest,
    this.enabled = true,
    required this.installedAt,
  });

  StremioAddonEntry copyWith({
    String? manifestUrl,
    StremioManifest? manifest,
    bool? enabled,
    DateTime? installedAt,
  }) {
    return StremioAddonEntry(
      manifestUrl: manifestUrl ?? this.manifestUrl,
      manifest: manifest ?? this.manifest,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'manifestUrl': manifestUrl,
    'manifest': manifest.toJson(),
    'enabled': enabled,
    'installedAt': installedAt.toIso8601String(),
  };

  factory StremioAddonEntry.fromJson(Map<String, dynamic> json) {
    final manifestData = json['manifest'] as Map<String, dynamic>? ?? {};
    return StremioAddonEntry(
      manifestUrl: (json['manifestUrl'] ?? '').toString(),
      manifest: StremioManifest.fromJson(manifestData),
      enabled: json['enabled'] != false,
      installedAt: DateTime.tryParse(json['installedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [manifestUrl, manifest, enabled, installedAt];
}

class StremioStore extends ChangeNotifier {
  StremioStore._(this._box);

  static const String boxName = 'stremio_addons';
  final Box<String> _box;

  static Future<StremioStore> init() async {
    final box = await openBoxSafely<String>(boxName);
    return StremioStore._(box);
  }

  List<StremioAddonEntry> all() {
    final result = <StremioAddonEntry>[];
    for (final raw in _box.values) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          result.add(StremioAddonEntry.fromJson(decoded));
        }
      } catch (_) {}
    }
    return result;
  }

  List<StremioAddonEntry> enabled() {
    return all().where((e) => e.enabled).toList();
  }

  StremioAddonEntry? get(String manifestUrl) {
    final raw = _box.get(manifestUrl);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StremioAddonEntry.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<void> save(StremioAddonEntry entry) async {
    final raw = jsonEncode(entry.toJson());
    await _box.put(entry.manifestUrl, raw);
    notifyListeners();
  }

  Future<void> setEnabled(String manifestUrl, bool enabled) async {
    final existing = get(manifestUrl);
    if (existing == null) return;
    await save(existing.copyWith(enabled: enabled));
  }

  Future<void> delete(String manifestUrl) async {
    await _box.delete(manifestUrl);
    notifyListeners();
  }

  bool contains(String manifestUrl) => _box.containsKey(manifestUrl);
}
