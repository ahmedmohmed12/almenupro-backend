import '../services/api_service.dart';

/// API origin without the `/api` suffix, e.g. https://almenupro-backend.vercel.app
String get menuImageApiOrigin {
  final base = ApiService.baseUrl;
  if (base.endsWith('/api')) {
    return base.substring(0, base.length - 4);
  }
  return base.replaceAll(RegExp(r'/api/?$'), '');
}

bool isLegacyTalabatImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return false;
  final host = uri.host.toLowerCase();
  return host.contains('deliveryhero.io') || host.contains('talabat.com');
}

bool isDirectOgImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.startsWith('/menu-images/') || isLocalMenuImagePath(trimmed)) {
    return true;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
    return false;
  }

  final path = uri.path.toLowerCase();
  if (RegExp(r'\.(png|jpe?g|gif|webp|svg|avif|ico)$', caseSensitive: false)
      .hasMatch(path)) {
    return true;
  }

  return path.contains('/menu-images/') || path.contains('/api/uploads/menu/');
}

bool isLocalMenuImagePath(String url) {
  final trimmed = url.trim();
  return trimmed.startsWith('/api/uploads/menu/');
}

bool isExternalHttpImageUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return false;
  return uri.scheme == 'http' || uri.scheme == 'https';
}

/// Extracts the filename from a legacy `/menu-images/` or local upload path.
String? menuImageFilenameFromPath(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  for (final marker in ['/menu-images/', '/api/uploads/menu/', '/api/items/image/']) {
    final index = trimmed.indexOf(marker);
    if (index >= 0) {
      final tail = trimmed.substring(index + marker.length).split('?').first.split('#').first;
      if (tail.isNotEmpty && !tail.contains('/')) return tail;
    }
  }

  return null;
}

/// Builds a browser-safe image URL (uses backend proxy for external CDNs).
String resolvePreviewImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  if (trimmed.contains('/api/image-proxy')) {
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return '$menuImageApiOrigin$trimmed';
  }

  final filename = menuImageFilenameFromPath(trimmed);
  if (filename != null) {
    return '$menuImageApiOrigin/api/uploads/menu/$filename';
  }

  if (isLocalMenuImagePath(trimmed)) {
    return '$menuImageApiOrigin$trimmed';
  }

  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    return '$menuImageApiOrigin$trimmed';
  }

  if (isExternalHttpImageUrl(trimmed)) {
    return '$menuImageApiOrigin/api/image-proxy?url=${Uri.encodeComponent(trimmed)}';
  }

  return trimmed;
}

/// Normalizes menu image paths for display. Prefers locally hosted Almenupro URLs
/// and ignores legacy Talabat CDN links that should be migrated on the server.
String resolveImageUrl(String url) => resolvePreviewImageUrl(url);

/// Used when parsing API payloads — keeps local paths, drops legacy CDN URLs.
String normalizeMenuImageUrl(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  if (isLocalMenuImagePath(value)) return value;
  if (isLegacyTalabatImageUrl(value)) return '';
  return value;
}
