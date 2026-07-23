import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

/// Rewrites third-party CDN URLs through our API proxy on Flutter Web so
/// CanvasKit can fetch image bytes without browser CORS blocks.
String resolveImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  if (!kIsWeb) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return trimmed;

  final host = uri.host.toLowerCase();
  final needsProxy = host.contains('deliveryhero.io') ||
      host.contains('talabat.com') ||
      host.contains('images.deliveryhero.io');

  if (!needsProxy) return trimmed;

  return '${ApiService.baseUrl}/image-proxy?url=${Uri.encodeComponent(trimmed)}';
}
