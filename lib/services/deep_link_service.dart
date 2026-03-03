import 'dart:async';

import 'package:app_links/app_links.dart';

class DeepLinkService {
  DeepLinkService._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _linkSub;

  static Future<void> initialize({
    required void Function(String listingId) onListingDeepLink,
  }) async {
    final initial = await _appLinks.getInitialLink();
    _handleUri(initial, onListingDeepLink);

    await _linkSub?.cancel();
    _linkSub = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri, onListingDeepLink),
      onError: (_) {},
    );
  }

  static void _handleUri(
    Uri? uri,
    void Function(String listingId) onListingDeepLink,
  ) {
    if (uri == null) return;
    final listingId = extractListingId(uri);
    if (listingId != null && listingId.trim().isNotEmpty) {
      onListingDeepLink(listingId.trim());
    }
  }

  static String? extractListingId(Uri uri) {
    final nestedLink = uri.queryParameters['link'];
    if (nestedLink != null && nestedLink.trim().isNotEmpty) {
      final nestedUri = Uri.tryParse(Uri.decodeComponent(nestedLink));
      if (nestedUri != null) {
        final nestedListing = extractListingId(nestedUri);
        if (nestedListing != null && nestedListing.trim().isNotEmpty) {
          return nestedListing;
        }
      }
    }

    final segments = uri.pathSegments;

    if (uri.scheme == 'https' || uri.scheme == 'http') {
      if (segments.length >= 2 && segments[0].toLowerCase() == 'listing') {
        return segments[1];
      }
    }

    if (uri.scheme.toLowerCase() == 'digitalarhat') {
      if (uri.host.toLowerCase() == 'listing' && segments.isNotEmpty) {
        return segments.first;
      }
      if (segments.length >= 2 && segments[0].toLowerCase() == 'listing') {
        return segments[1];
      }
    }

    return uri.queryParameters['listingId'];
  }

  static Future<void> dispose() async {
    await _linkSub?.cancel();
    _linkSub = null;
  }
}

