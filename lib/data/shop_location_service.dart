import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../domain/models.dart';

class ShopGpsFix {
  const ShopGpsFix(this.latitude, this.longitude, this.accuracy);
  final double latitude, longitude, accuracy;
}

class ShopAddress {
  const ShopAddress({this.address = '', this.area = '', this.postalCode = ''});
  final String address, area, postalCode;
}

class ShopLocationException implements Exception {
  const ShopLocationException(this.message, {this.settingsNeeded = false});
  final String message;
  final bool settingsNeeded;
}

abstract class ShopLocationService {
  Future<ShopGpsFix> capture();
  Future<ShopAddress?> addressFor(ShopGpsFix fix);
}

class DeviceShopLocationService implements ShopLocationService {
  @override
  Future<ShopGpsFix> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ShopLocationException(
        'Turn on the phone’s location service and try again.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ShopLocationException(
        'Allow location access in the phone’s app settings.',
        settingsNeeded: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const ShopLocationException(
        'Location permission is needed to capture the shop entrance.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
    if (!validCoordinates(position.latitude, position.longitude) ||
        !position.accuracy.isFinite ||
        position.accuracy < 0) {
      throw const ShopLocationException(
        'No usable GPS fix was returned. Try again outdoors.',
      );
    }
    return ShopGpsFix(position.latitude, position.longitude, position.accuracy);
  }

  @override
  Future<ShopAddress?> addressFor(ShopGpsFix fix) async {
    final marks = await Geocoding()
        .placemarkFromCoordinates(fix.latitude, fix.longitude)
        .timeout(const Duration(seconds: 8));
    if (marks.isEmpty) return null;
    final p = marks.first;
    final parts = <String>[];
    for (final value in [
      p.street,
      p.subLocality,
      p.locality,
      p.subAdministrativeArea,
      p.administrativeArea,
    ]) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty &&
          !parts.any((s) => s.toLowerCase() == text.toLowerCase())) {
        parts.add(text);
      }
    }
    final postal = p.postalCode?.trim() ?? '';
    return ShopAddress(
      address: parts.join(', '),
      area: (p.subLocality?.trim().isNotEmpty ?? false)
          ? p.subLocality!
          : p.locality ?? '',
      postalCode: RegExp(r'^[1-9][0-9]{5}$').hasMatch(postal) ? postal : '',
    );
  }
}
