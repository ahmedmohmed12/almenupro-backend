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

bool isLocalMenuImagePath(String url) {
  final trimmed = url.trim();
  return trimmed.startsWith('/menu-images/') ||
      trimmed.startsWith('/api/uploads/menu/');
}

String? localMenuImageFilename(String url) {
  final trimmed = url.trim();
  if (!isLocalMenuImagePath(trimmed)) return null;
  final parts = trimmed.split('/');
  return parts.isEmpty ? null : parts.last;
}

/// Normalizes menu image paths for display. Prefers locally hosted Almenupro URLs
/// and ignores legacy Talabat CDN links that should be migrated on the server.
String resolveImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  final filename = localMenuImageFilename(trimmed);
  if (filename != null && filename.isNotEmpty) {
    return '${ApiService.baseUrl}/items/image/$filename';
  }

  if (isLegacyTalabatImageUrl(trimmed)) {
    return '';
  }

  if (trimmed.startsWith('/')) {
    return '$menuImageApiOrigin$trimmed';
  }

  return trimmed;
}

/// Used when parsing API payloads — keeps local paths, drops legacy CDN URLs.
String normalizeMenuImageUrl(Object? raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  if (isLocalMenuImagePath(value)) return value;
  if (isLegacyTalabatImageUrl(value)) return '';
  return value;
}
