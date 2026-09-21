import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';

import '../aniyomi/aniyomi_image_provider.dart';
import '../cache/app_image_cache.dart';
import '../mihon/mihon_image_provider.dart';

/// Central cover-image provider dispatcher for the shared card/hero widgets.
///
/// Routes Cloudflare-walled **Aniyomi** (`x-ani-src`) and **Mihon**
/// (`x-mihon-src`) covers through their native, `cf_clearance`-carrying image
/// path ([AniyomiImage] / [MihonImage]); every other source falls back to the
/// normal [CachedNetworkImageProvider]. The markers are internal header keys and
/// are never sent over the network.
///
/// Also synthesizes missing `User-Agent` and `Referer` headers to prevent `403 Forbidden`
/// errors on image hosts / CDNs with anti-hotlinking protection (e.g. SpeedPorn / Himeros).
Map<String, String>? resolveEffectiveCoverHeaders(
  String? url,
  Map<String, String>? headers, {
  String? showUrl,
  String? sourceId,
}) {
  final out = <String, String>{};
  if (headers != null) out.addAll(headers);

  // If user-agent is missing, add a standard browser user-agent
  final hasUa = out.keys.any((k) => k.toLowerCase() == 'user-agent');
  if (!hasUa) {
    out['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  // If referer is missing, synthesize from showUrl or cover url origin
  final hasReferer = out.keys.any((k) => k.toLowerCase() == 'referer');
  if (!hasReferer) {
    if (showUrl != null && showUrl.startsWith('http')) {
      try {
        final uri = Uri.parse(showUrl);
        out['Referer'] = '${uri.scheme}://${uri.host}/';
      } catch (_) {}
    } else if (url != null && url.startsWith('http')) {
      try {
        final uri = Uri.parse(url);
        out['Referer'] = '${uri.scheme}://${uri.host}/';
      } catch (_) {}
    }
  }
  return out.isEmpty ? null : out;
}

ImageProvider nativeCoverProvider(
  String url,
  Map<String, String>? headers, {
  String? showUrl,
  String? sourceId,
}) {
  final ani = headers?['x-ani-src'];
  if (ani != null) {
    final id = int.tryParse(ani);
    if (id != null) return AniyomiImage(id, url);
  }
  final mihon = headers?['x-mihon-src'];
  if (mihon != null) {
    final id = int.tryParse(mihon);
    if (id != null) return MihonImage(id, url);
  }
  final effectiveHeaders = resolveEffectiveCoverHeaders(
    url,
    headers,
    showUrl: showUrl,
    sourceId: sourceId,
  );
  return AppImageCache.imageProvider(url, headers: effectiveHeaders);
}
