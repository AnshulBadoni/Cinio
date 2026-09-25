import 'package:equatable/equatable.dart';

class StremioCatalogDescriptor extends Equatable {
  final String type;
  final String id;
  final String? name;
  final List<String>? extraSupported;
  final List<String>? extraRequired;

  const StremioCatalogDescriptor({
    required this.type,
    required this.id,
    this.name,
    this.extraSupported,
    this.extraRequired,
  });

  factory StremioCatalogDescriptor.fromJson(Map<String, dynamic> json) {
    return StremioCatalogDescriptor(
      type: (json['type'] ?? 'movie').toString(),
      id: (json['id'] ?? '').toString(),
      name: json['name']?.toString(),
      extraSupported: (json['extraSupported'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      extraRequired: (json['extraRequired'] as List?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    if (name != null) 'name': name,
    if (extraSupported != null) 'extraSupported': extraSupported,
    if (extraRequired != null) 'extraRequired': extraRequired,
  };

  @override
  List<Object?> get props => [type, id, name, extraSupported, extraRequired];
}

class StremioResourceObject extends Equatable {
  final String name;
  final List<String> types;
  final List<String>? idPrefixes;

  const StremioResourceObject({
    required this.name,
    required this.types,
    this.idPrefixes,
  });

  factory StremioResourceObject.fromJson(dynamic json) {
    if (json is String) {
      return StremioResourceObject(
        name: json,
        types: const ['movie', 'series', 'anime'],
      );
    }
    if (json is Map<String, dynamic>) {
      final name = (json['name'] ?? '').toString();
      final types = (json['types'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['movie', 'series', 'anime'];
      final idPrefixes = (json['idPrefixes'] as List?)
          ?.map((e) => e.toString())
          .toList();
      return StremioResourceObject(
        name: name,
        types: types,
        idPrefixes: idPrefixes,
      );
    }
    return const StremioResourceObject(name: '', types: []);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'types': types,
    if (idPrefixes != null) 'idPrefixes': idPrefixes,
  };

  @override
  List<Object?> get props => [name, types, idPrefixes];
}

class StremioManifest extends Equatable {
  final String id;
  final String name;
  final String version;
  final String? description;
  final List<StremioResourceObject> resources;
  final List<String> types;
  final List<String> idPrefixes;
  final List<StremioCatalogDescriptor> catalogs;
  final String? logo;
  final String? background;
  final bool isNsfw;
  final bool isP2p;
  final bool configurable;
  final bool configurationRequired;

  const StremioManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.resources = const [],
    this.types = const [],
    this.idPrefixes = const [],
    this.catalogs = const [],
    this.logo,
    this.background,
    this.isNsfw = false,
    this.isP2p = false,
    this.configurable = false,
    this.configurationRequired = false,
  });

  factory StremioManifest.fromJson(Map<String, dynamic> json) {
    final rawResources = json['resources'] as List? ?? const [];
    final resources = rawResources
        .map((r) => StremioResourceObject.fromJson(r))
        .where((r) => r.name.isNotEmpty)
        .toList();

    final rawTypes = json['types'] as List? ?? const [];
    final types = rawTypes.map((e) => e.toString()).toList();

    final rawPrefixes = json['idPrefixes'] as List? ?? const [];
    final idPrefixes = rawPrefixes.map((e) => e.toString()).toList();

    final rawCatalogs = json['catalogs'] as List? ?? const [];
    final catalogs = rawCatalogs
        .whereType<Map<String, dynamic>>()
        .map((c) => StremioCatalogDescriptor.fromJson(c))
        .toList();

    final behaviorHints = json['behaviorHints'] as Map<String, dynamic>? ?? {};
    final isAdult = (behaviorHints['adult'] == true) ||
        (json['adult'] == true);
    final isP2p = (behaviorHints['p2p'] == true) ||
        (json['p2p'] == true);
    final configurable = behaviorHints['configurable'] == true;
    final configurationRequired =
        behaviorHints['configurationRequired'] == true;

    return StremioManifest(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Unnamed Addon').toString(),
      version: (json['version'] ?? '1.0.0').toString(),
      description: json['description']?.toString(),
      resources: resources,
      types: types,
      idPrefixes: idPrefixes,
      catalogs: catalogs,
      logo: json['logo']?.toString(),
      background: json['background']?.toString(),
      isNsfw: isAdult,
      isP2p: isP2p,
      configurable: configurable,
      configurationRequired: configurationRequired,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    if (description != null) 'description': description,
    'resources': resources.map((r) => r.toJson()).toList(),
    'types': types,
    'idPrefixes': idPrefixes,
    'catalogs': catalogs.map((c) => c.toJson()).toList(),
    if (logo != null) 'logo': logo,
    if (background != null) 'background': background,
    'behaviorHints': {
      if (isNsfw) 'adult': true,
      if (isP2p) 'p2p': true,
      if (configurable) 'configurable': true,
      if (configurationRequired) 'configurationRequired': true,
    },
  };

  bool supportsResource(String resourceName, {String? type}) {
    for (final res in resources) {
      if (res.name == resourceName) {
        if (type == null || res.types.isEmpty || res.types.contains(type)) {
          return true;
        }
      }
    }
    return false;
  }

  bool get supportsStreams => supportsResource('stream');
  bool get supportsCatalogs => supportsResource('catalog');
  bool get supportsSubtitles => supportsResource('subtitles');

  @override
  List<Object?> get props => [
    id,
    name,
    version,
    description,
    resources,
    types,
    idPrefixes,
    catalogs,
    logo,
    background,
    isNsfw,
    isP2p,
    configurable,
    configurationRequired,
  ];
}
