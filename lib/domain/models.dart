import 'google_maps_link.dart';

enum UserRole { owner, driver }

class AppProfile {
  const AppProfile({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final UserRole role;

  factory AppProfile.fromMap(Map<String, dynamic> map) => AppProfile(
    id: map['id'] as String,
    name: map['display_name'] as String,
    role: UserRole.values.byName(map['role'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'display_name': name,
    'role': role.name,
  };
}

class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.area,
    this.address = '',
    this.landmark = '',
    this.phone = '',
    this.contactName = '',
    this.postalCode = '',
    this.notes = '',
    this.mapsUrl = '',
    this.latitude,
    this.longitude,
    this.verified = false,
    this.photoPath,
    this.localPhotoPath,
    this.version = 0,
  });

  final String id,
      name,
      area,
      address,
      landmark,
      phone,
      contactName,
      postalCode,
      notes,
      mapsUrl;
  final double? latitude, longitude;
  final bool verified;
  final String? photoPath, localPhotoPath;
  final int version;

  bool get hasCoordinates => validCoordinates(latitude, longitude);
  bool get hasMapsLink => isGoogleMapsLink(mapsUrl);
  bool get hasLocation => hasCoordinates || hasMapsLink;
  bool get readyForDelivery => hasMapsLink || (hasCoordinates && verified);
  String get locationStatus => readyForDelivery
      ? 'Ready for delivery'
      : hasCoordinates
      ? 'Needs verification'
      : 'Needs location';
  String get locationDescription => hasMapsLink
      ? 'Google Maps location saved'
      : verified && hasCoordinates
      ? 'Verified entrance location'
      : locationStatus;

  factory Shop.fromMap(Map<String, dynamic> map) => Shop(
    id: map['id'] as String,
    name: map['name'] as String,
    area: map['area'] as String,
    address: map['address'] as String? ?? '',
    landmark: map['landmark'] as String? ?? '',
    phone: map['phone'] as String? ?? '',
    contactName: map['contact_name'] as String? ?? '',
    postalCode: map['postal_code'] as String? ?? '',
    notes: map['notes'] as String? ?? '',
    mapsUrl: map['maps_url'] as String? ?? '',
    latitude: (map['latitude'] as num?)?.toDouble(),
    longitude: (map['longitude'] as num?)?.toDouble(),
    verified: map['verified'] == true || map['verified'] == 1,
    photoPath: map['photo_path'] as String?,
    localPhotoPath: map['local_photo_path'] as String?,
    version: map['version'] as int? ?? 0,
  );

  Map<String, Object?> toMap({bool local = false}) => {
    'id': id,
    'name': name,
    'area': area,
    'address': address,
    'landmark': landmark,
    'phone': phone,
    'contact_name': contactName,
    'postal_code': postalCode,
    'notes': notes,
    'maps_url': mapsUrl,
    'latitude': latitude,
    'longitude': longitude,
    'verified': local ? (verified ? 1 : 0) : verified,
    'photo_path': photoPath,
    if (local) 'local_photo_path': localPhotoPath,
    'version': version,
  };

  Shop withPhoto(String? remotePath, String? localPath) => Shop(
    id: id,
    name: name,
    area: area,
    address: address,
    landmark: landmark,
    phone: phone,
    contactName: contactName,
    postalCode: postalCode,
    notes: notes,
    mapsUrl: mapsUrl,
    latitude: latitude,
    longitude: longitude,
    verified: verified,
    photoPath: remotePath,
    localPhotoPath: localPath,
    version: version,
  );
}

enum VisitStatus { pending, delivered, failed }

extension VisitStatusLabel on VisitStatus {
  String get label => switch (this) {
    VisitStatus.pending => 'Pending',
    VisitStatus.delivered => 'Delivered',
    VisitStatus.failed => 'Could not deliver',
  };
}

class DeliveryStop {
  const DeliveryStop({
    required this.id,
    required this.shopId,
    required this.date,
    required this.driverId,
    required this.order,
    this.status = VisitStatus.pending,
    this.reason = '',
    this.version = 0,
  });
  final String id, shopId, date, driverId, reason;
  final int order, version;
  final VisitStatus status;

  DeliveryStop withOrder(int next) => DeliveryStop(
    id: id,
    shopId: shopId,
    date: date,
    driverId: driverId,
    order: next,
    status: status,
    reason: reason,
    version: version,
  );

  factory DeliveryStop.fromMap(Map<String, dynamic> map) => DeliveryStop(
    id: map['id'] as String,
    shopId: map['shop_id'] as String,
    date: map['service_date'] as String,
    driverId: map['driver_id'] as String,
    order: map['stop_order'] as int,
    status: VisitStatus.values.byName(map['status'] as String),
    reason: map['reason'] as String? ?? '',
    version: map['version'] as int? ?? 0,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'shop_id': shopId,
    'service_date': date,
    'driver_id': driverId,
    'stop_order': order,
    'status': status.name,
    'reason': reason,
    'version': version,
  };

  DeliveryStop withStatus(VisitStatus next, String note) => DeliveryStop(
    id: id,
    shopId: shopId,
    date: date,
    driverId: driverId,
    order: order,
    status: next,
    reason: note,
    version: version,
  );
}

class PendingVisit {
  const PendingVisit({
    required this.operationId,
    required this.stopId,
    required this.status,
    required this.reason,
    required this.expectedVersion,
  });
  final String operationId, stopId, reason;
  final VisitStatus status;
  final int expectedVersion;

  factory PendingVisit.fromMap(Map<String, dynamic> map) => PendingVisit(
    operationId: map['operation_id'] as String,
    stopId: map['stop_id'] as String,
    status: VisitStatus.values.byName(map['status'] as String),
    reason: map['reason'] as String,
    expectedVersion: map['expected_version'] as int,
  );

  Map<String, Object?> toMap() => {
    'operation_id': operationId,
    'stop_id': stopId,
    'status': status.name,
    'reason': reason,
    'expected_version': expectedVersion,
  };
}

bool validCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String readableDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

Uri navigationUri(Shop shop) {
  if (!shop.readyForDelivery) {
    throw StateError(
      'Add a Google Maps link or verify the shop entrance location.',
    );
  }
  if (shop.hasMapsLink) return googleMapsUri(shop.mapsUrl);
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${shop.latitude},${shop.longitude}',
    'travelmode': 'driving',
    'dir_action': 'navigate',
  });
}

Uri locationPreviewUri(Shop shop) {
  if (shop.hasMapsLink) return googleMapsUri(shop.mapsUrl);
  if (!shop.hasCoordinates) throw StateError('Add the shop location first.');
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '${shop.latitude},${shop.longitude}',
  });
}
