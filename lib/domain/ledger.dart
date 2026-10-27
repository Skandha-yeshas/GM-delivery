import 'models.dart';

const maxMoneyPaise = 100000000000;

int parsePaise(String text) {
  final value = text.trim().replaceFirst(RegExp(r'^₹\s*'), '');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException(
      'Enter rupees with at most two decimal places.',
    );
  }
  final parts = value.split('.');
  final whole = int.parse(parts.first);
  if (whole > maxMoneyPaise ~/ 100) {
    throw const FormatException('Amount is too large.');
  }
  final amount =
      whole * 100 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (amount > maxMoneyPaise) {
    throw const FormatException('Amount is too large.');
  }
  return amount;
}

String rupees(int paise, {bool symbol = true}) =>
    '${paise < 0 ? '-' : ''}${symbol ? '₹' : ''}${paise.abs() ~/ 100}.${(paise.abs() % 100).toString().padLeft(2, '0')}';

enum PaymentMode { cash, upi, cheque, credit }

enum LedgerKind { bill, payment, opening, correction, flag }

class CollectionLocation {
  const CollectionLocation({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.status = 'unavailable',
  });
  final double? latitude, longitude, accuracy;
  final String status;
}

class LedgerCommand {
  const LedgerCommand({
    required this.operationId,
    required this.shopId,
    required this.kind,
    required this.capturedAt,
    this.stopId,
    this.expectedStopVersion,
    this.legacyVisitOperationId,
    this.originalId,
    this.expectedRevision = 0,
    this.billNumber = '',
    this.billPaise = 0,
    this.collectedPaise = 0,
    this.mode = PaymentMode.credit,
    this.reference = '',
    this.note = '',
    this.reason = '',
    this.collectNextVisit,
    this.location = const CollectionLocation(),
  });
  final String operationId, shopId, billNumber, reference, note, reason;
  final String? stopId, originalId, legacyVisitOperationId;
  final int? expectedStopVersion;
  final int expectedRevision, billPaise, collectedPaise;
  final LedgerKind kind;
  final PaymentMode mode;
  final DateTime capturedAt;
  final bool? collectNextVisit;
  final CollectionLocation location;

  void validate({LedgerKind? correctedKind}) {
    if (billPaise < 0 ||
        collectedPaise < 0 ||
        billPaise > maxMoneyPaise ||
        collectedPaise > maxMoneyPaise) {
      throw const FormatException('Amounts must be valid, non-negative paise.');
    }
    final type = correctedKind ?? kind;
    if (type == LedgerKind.bill &&
        (billNumber.trim().isEmpty ||
            (billPaise == 0 && kind != LedgerKind.correction) ||
            collectedPaise > billPaise)) {
      throw const FormatException(
        'Enter a bill number and positive bill amount. Collection cannot exceed this bill.',
      );
    }
    if (type == LedgerKind.payment &&
        (billPaise != 0 ||
            (collectedPaise == 0 && kind != LedgerKind.correction) ||
            mode == PaymentMode.credit)) {
      throw const FormatException(
        'Enter a positive payment in cash, UPI or cheque.',
      );
    }
    if (type == LedgerKind.opening &&
        (collectedPaise != 0 || mode != PaymentMode.credit)) {
      throw const FormatException(
        'An opening balance cannot contain a payment.',
      );
    }
    if (kind == LedgerKind.correction &&
        (originalId == null || expectedRevision < 1 || reason.trim().isEmpty)) {
      throw const FormatException(
        'A correction needs the original entry, its version and a reason.',
      );
    }
    if (kind == LedgerKind.flag &&
        (collectNextVisit == null || billPaise != 0 || collectedPaise != 0)) {
      throw const FormatException(
        'Choose whether to collect on the next visit.',
      );
    }
    if ((mode == PaymentMode.credit && collectedPaise != 0) ||
        (mode != PaymentMode.credit &&
            collectedPaise == 0 &&
            type == LedgerKind.bill)) {
      throw const FormatException(
        'Choose Credit for no payment, or enter the collected amount.',
      );
    }
    if (billNumber.length > 100 ||
        reference.length > 200 ||
        note.length > 1000 ||
        reason.length > 500) {
      throw const FormatException(
        'The bill number, reference or note is too long.',
      );
    }
    if (![
          'available',
          'unavailable',
          'denied',
          'timeout',
        ].contains(location.status) ||
        (location.status == 'available' &&
            (!validCoordinates(location.latitude, location.longitude) ||
                location.accuracy == null ||
                !location.accuracy!.isFinite ||
                location.accuracy! < 0))) {
      throw const FormatException('Invalid collection location.');
    }
  }

  Map<String, dynamic> toMap() => {
    'operation_id': operationId,
    'shop_id': shopId,
    'kind': kind.name,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'stop_id': stopId,
    'expected_stop_version': expectedStopVersion,
    'legacy_visit_operation_id': legacyVisitOperationId,
    'original_id': originalId,
    'expected_revision': expectedRevision,
    'bill_number': billNumber.trim(),
    'bill_paise': billPaise,
    'collected_paise': collectedPaise,
    'mode': mode.name,
    'reference': reference.trim(),
    'note': note.trim(),
    'reason': reason.trim(),
    'collect_next_visit': collectNextVisit,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'accuracy': location.accuracy,
    'gps_status': location.status,
  };

  factory LedgerCommand.fromMap(Map<String, dynamic> m) => LedgerCommand(
    operationId: m['operation_id'] as String,
    shopId: m['shop_id'] as String,
    kind: LedgerKind.values.byName(m['kind'] as String),
    capturedAt: DateTime.parse(m['captured_at'] as String),
    stopId: m['stop_id'] as String?,
    expectedStopVersion: (m['expected_stop_version'] as num?)?.toInt(),
    legacyVisitOperationId: m['legacy_visit_operation_id'] as String?,
    originalId: m['original_id'] as String?,
    expectedRevision: (m['expected_revision'] as num?)?.toInt() ?? 0,
    billNumber: m['bill_number'] as String? ?? '',
    billPaise: (m['bill_paise'] as num?)?.toInt() ?? 0,
    collectedPaise: (m['collected_paise'] as num?)?.toInt() ?? 0,
    mode: PaymentMode.values.byName(m['mode'] as String? ?? 'credit'),
    reference: m['reference'] as String? ?? '',
    note: m['note'] as String? ?? '',
    reason: m['reason'] as String? ?? '',
    collectNextVisit: m['collect_next_visit'] as bool?,
    location: CollectionLocation(
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      accuracy: (m['accuracy'] as num?)?.toDouble(),
      status: m['gps_status'] as String? ?? 'unavailable',
    ),
  );
}

class LedgerEntry {
  const LedgerEntry({
    required this.command,
    required this.actorId,
    required this.sequence,
    required this.revision,
    required this.debitDelta,
    required this.creditDelta,
    required this.recordedAt,
    this.stopAfter,
  });
  final LedgerCommand command;
  final String actorId;
  final int sequence, revision, debitDelta, creditDelta;
  final DateTime recordedAt;
  final DeliveryStop? stopAfter;
  String get id => command.operationId;
  String get rootId => command.originalId ?? id;
  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
    command: LedgerCommand.fromMap(
      Map<String, dynamic>.from(m['payload'] as Map),
    ),
    actorId: m['actor_id'] as String,
    sequence: (m['sequence'] as num).toInt(),
    revision: (m['revision'] as num).toInt(),
    debitDelta: (m['debit_delta'] as num).toInt(),
    creditDelta: (m['credit_delta'] as num).toInt(),
    recordedAt: DateTime.parse(m['recorded_at'] as String),
    stopAfter: m['stop_after'] == null
        ? null
        : DeliveryStop.fromMap(
            Map<String, dynamic>.from(m['stop_after'] as Map),
          ),
  );
  Map<String, dynamic> toMap() => {
    'operation_id': id,
    'shop_id': command.shopId,
    'payload': command.toMap(),
    'actor_id': actorId,
    'sequence': sequence,
    'revision': revision,
    'debit_delta': debitDelta,
    'credit_delta': creditDelta,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'stop_after': stopAfter?.toMap(),
  };
}

class PendingLedger {
  const PendingLedger(this.command, this.actorId, {this.error});
  final LedgerCommand command;
  final String actorId;
  final String? error;
}

class CreditBalance {
  const CreditBalance({
    required this.shopId,
    this.balancePaise = 0,
    this.version = 0,
    this.oldestUnpaidAt,
    this.lastPaymentAt,
    this.collectNextVisit = false,
    this.flagRevision = 0,
  });
  final String shopId;
  final int balancePaise, version, flagRevision;
  final DateTime? oldestUnpaidAt, lastPaymentAt;
  final bool collectNextVisit;
  factory CreditBalance.fromMap(Map<String, dynamic> m) => CreditBalance(
    shopId: m['shop_id'] as String,
    balancePaise: (m['balance_paise'] as num).toInt(),
    version: (m['version'] as num?)?.toInt() ?? 0,
    oldestUnpaidAt: DateTime.tryParse(m['oldest_unpaid_at'] as String? ?? ''),
    lastPaymentAt: DateTime.tryParse(m['last_payment_at'] as String? ?? ''),
    collectNextVisit: m['collect_next_visit'] == true,
    flagRevision: (m['flag_revision'] as num?)?.toInt() ?? 0,
  );
  Map<String, dynamic> toMap() => {
    'shop_id': shopId,
    'balance_paise': balancePaise,
    'version': version,
    'oldest_unpaid_at': oldestUnpaidAt?.toUtc().toIso8601String(),
    'last_payment_at': lastPaymentAt?.toUtc().toIso8601String(),
    'collect_next_visit': collectNextVisit,
    'flag_revision': flagRevision,
  };
}

class EffectiveLedgerEntry {
  const EffectiveLedgerEntry(this.original, this.latest);
  final LedgerEntry original, latest;
  LedgerCommand get values => latest.command;
}

List<EffectiveLedgerEntry> effectiveLedger(List<LedgerEntry> entries) {
  final roots = <String, LedgerEntry>{}, latest = <String, LedgerEntry>{};
  for (final entry in entries) {
    if (entry.command.kind == LedgerKind.flag) continue;
    if (entry.command.kind != LedgerKind.correction) roots[entry.id] = entry;
    if ((latest[entry.rootId]?.revision ?? 0) < entry.revision) {
      latest[entry.rootId] = entry;
    }
  }
  return [
    for (final root in roots.values)
      EffectiveLedgerEntry(root, latest[root.id]!),
  ];
}

CreditBalance calculateCreditBalance(String shopId, List<LedgerEntry> entries) {
  final rows = entries.where((e) => e.command.shopId == shopId).toList()
    ..sort((a, b) => a.sequence.compareTo(b.sequence));
  final effective = effectiveLedger(rows)
    ..sort((a, b) => a.original.sequence.compareTo(b.original.sequence));
  final credits = rows.fold<int>(0, (n, e) => n + e.creditDelta);
  var debit = 0;
  DateTime? oldest, lastPayment;
  for (final entry in effective) {
    debit += entry.values.billPaise;
    if (oldest == null && debit > credits) {
      oldest = entry.original.command.capturedAt;
    }
    if (entry.values.collectedPaise > 0 &&
        (lastPayment == null ||
            entry.original.command.capturedAt.isAfter(lastPayment))) {
      lastPayment = entry.original.command.capturedAt;
    }
  }
  final flag = rows.where((e) => e.command.kind == LedgerKind.flag).lastOrNull;
  final balance = rows.fold<int>(0, (n, e) => n + e.debitDelta - e.creditDelta);
  return CreditBalance(
    shopId: shopId,
    balancePaise: balance,
    version: rows.lastOrNull?.sequence ?? 0,
    oldestUnpaidAt: balance > 0 ? oldest : null,
    lastPaymentAt: lastPayment,
    collectNextVisit: flag?.command.collectNextVisit ?? false,
    flagRevision: flag?.revision ?? 0,
  );
}
