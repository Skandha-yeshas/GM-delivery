import 'dart:convert';
import 'models.dart';

int compareRouteStops(DeliveryStop a, DeliveryStop b) {
  final order = a.order.compareTo(b.order);
  return order == 0 ? a.id.compareTo(b.id) : order;
}

/// A complete route snapshot prevents one owner's draft overwriting another
/// owner's edits or a driver's newly completed visit.
class RouteOrderCommand {
  RouteOrderCommand({
    required this.operationId,
    required this.driverId,
    required this.date,
    required List<DeliveryStop> expected,
    required List<String> pendingIds,
  }) : expected = List.unmodifiable(expected.toList()..sort(compareRouteStops)),
       pendingIds = List.unmodifiable(pendingIds);

  final String operationId, driverId, date;
  final List<DeliveryStop> expected;
  final List<String> pendingIds;

  static List<Map<String, Object>> snapshot(Iterable<DeliveryStop> stops) =>
      (stops.toList()..sort((a, b) => a.id.compareTo(b.id)))
          .map(
            (s) => <String, Object>{
              'id': s.id,
              'stop_order': s.order,
              'version': s.version,
              'status': s.status.name,
            },
          )
          .toList();

  bool matches(Iterable<DeliveryStop> current) =>
      jsonEncode(snapshot(current)) == jsonEncode(snapshot(expected));

  List<DeliveryStop> arrange() {
    final pending = expected
        .where((s) => s.status == VisitStatus.pending)
        .toList();
    if (expected.isEmpty ||
        expected.any((s) => s.date != date || s.driverId != driverId) ||
        expected.map((s) => s.id).toSet().length != expected.length ||
        pendingIds.length != pending.length ||
        pendingIds.toSet().length != pending.length ||
        !pendingIds.toSet().containsAll(pending.map((s) => s.id))) {
      throw StateError(
        'Invalid route. Refresh and select the pending shops again.',
      );
    }
    final byId = {for (final s in pending) s.id: s};
    var next = 0;
    return [
      for (var i = 0; i < expected.length; i++)
        (expected[i].status == VisitStatus.pending
                ? byId[pendingIds[next++]]!
                : expected[i])
            .withOrder(i + 1),
    ];
  }

  Map<String, Object> toMap() => {
    'operation_id': operationId,
    'driver_id': driverId,
    'service_date': date,
    'expected': snapshot(expected),
    'pending_ids': pendingIds,
  };
}
