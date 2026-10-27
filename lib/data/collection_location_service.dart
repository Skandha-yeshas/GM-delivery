import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';

abstract class CollectionLocationService {
  Future<CollectionLocation> capture();
}

class DeviceCollectionLocationService implements CollectionLocationService {
  @override
  Future<CollectionLocation> capture() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const CollectionLocation();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if ([
        LocationPermission.denied,
        LocationPermission.deniedForever,
      ].contains(permission)) {
        return const CollectionLocation(status: 'denied');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!validCoordinates(position.latitude, position.longitude) ||
          !position.accuracy.isFinite ||
          position.accuracy < 0) {
        return const CollectionLocation();
      }
      return CollectionLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        status: 'available',
      );
    } on TimeoutException {
      return const CollectionLocation(status: 'timeout');
    } catch (_) {
      return const CollectionLocation();
    }
  }
}
