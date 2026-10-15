import 'models.dart';
import 'google_maps_link.dart';
export 'google_maps_link.dart';

class MapPin {
  const MapPin(this.latitude, this.longitude);
  final double latitude, longitude;
}

MapPin? _pin(String? latitude, String? longitude) {
  final lat = double.tryParse(latitude ?? '');
  final lng = double.tryParse(longitude ?? '');
  return validCoordinates(lat, lng) ? MapPin(lat!, lng!) : null;
}

/// Only extract a destination or place pin. An /@lat,lng view is a camera
/// position, which can be far from the selected shop; it is never used as a pin.
MapPin? pinFromMapsUri(Uri uri) {
  googleMapsUri(uri.toString());
  final decoded = Uri.decodeComponent(uri.toString());
  final place = RegExp(
    r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)',
  ).allMatches(decoded).lastOrNull;
  if (place != null) return _pin(place[1], place[2]);
  for (final key in ['destination', 'query', 'q']) {
    final value = uri.queryParameters[key]?.replaceFirst(RegExp(r'^loc:'), '');
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(value ?? '');
    if (match != null) return _pin(match[1], match[2]);
  }
  final path = RegExp(
    r'/maps/(?:search|place)/(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)(?:/|$)',
  ).firstMatch(Uri.decodeComponent(uri.path));
  return path == null ? null : _pin(path[1], path[2]);
}

Uri shopSearchUri(String name, String address, String area) =>
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': [
        name,
        address,
        if (area != 'Area not set') area,
      ].where((s) => s.trim().isNotEmpty).join(', '),
    });
