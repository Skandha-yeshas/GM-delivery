import 'dart:io';
import '../domain/maps_location.dart';

/// Follows only Google Maps redirects, without a paid geocoding service.
class MapsLinkResolver {
  Future<MapPin?> resolve(String link) async {
    var uri = googleMapsUri(link);
    var pin = pinFromMapsUri(uri);
    if (pin != null) return pin;
    if (uri.host != 'maps.app.goo.gl' && uri.host != 'goo.gl') return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      for (var redirect = 0; redirect < 5; redirect++) {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 6));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 6),
        );
        final location = response.headers.value(HttpHeaders.locationHeader);
        final isRedirect = [
          301,
          302,
          303,
          307,
          308,
        ].contains(response.statusCode);
        await response.listen((_) {}).cancel();
        if (!isRedirect || location == null) return null;
        uri = googleMapsUri(uri.resolve(location).toString());
        pin = pinFromMapsUri(uri);
        if (pin != null) return pin;
      }
    } on Exception {
      // Keep the original link available for manual preview and later retry.
    } finally {
      client.close(force: true);
    }
    return null;
  }
}
