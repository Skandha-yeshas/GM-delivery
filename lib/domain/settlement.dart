import 'ledger.dart';
import 'models.dart';

enum SettlementAction { submit, approve, reopen }

class SettlementTotals {
  const SettlementTotals({
    this.bills = 0,
    this.oldPayments = 0,
    this.cash = 0,
    this.upi = 0,
    this.cheque = 0,
    this.credit = 0,
    this.ledgerVersion = 0,
  });
  final int bills, oldPayments, cash, upi, cheque, credit, ledgerVersion;
  int get expectedCash => bills + oldPayments - upi - cheque - credit;
  Map<String, dynamic> toMap() => {
    'bills': bills,
    'old_payments': oldPayments,
    'cash': cash,
    'upi': upi,
    'cheque': cheque,
    'credit': credit,
    'ledger_version': ledgerVersion,
  };
  factory SettlementTotals.fromMap(Map<String, dynamic> m) => SettlementTotals(
    bills: (m['bills'] as num).toInt(),
    oldPayments: (m['old_payments'] as num).toInt(),
    cash: (m['cash'] as num).toInt(),
    upi: (m['upi'] as num).toInt(),
    cheque: (m['cheque'] as num).toInt(),
    credit: (m['credit'] as num).toInt(),
    ledgerVersion: (m['ledger_version'] as num).toInt(),
  );
}

// Original immutable stop receipt fixes attribution even after a correction.
SettlementTotals settlementTotals(
  List<LedgerEntry> entries,
  List<DeliveryStop> stops,
  String driverId,
  String date,
) {
  var bills = 0,
      old = 0,
      cash = 0,
      upi = 0,
      cheque = 0,
      credit = 0,
      version = 0;
  for (final e in effectiveLedger(entries)) {
    if (![
      LedgerKind.bill,
      LedgerKind.payment,
    ].contains(e.original.command.kind)) {
      continue;
    }
    final stop =
        e.original.stopAfter ??
        stops.where((s) => s.id == e.original.command.stopId).firstOrNull;
    if (stop?.driverId != driverId || stop?.date != date) continue;
    final v = e.values;
    if (e.original.command.kind == LedgerKind.bill) {
      bills += v.billPaise;
      credit += v.billPaise - v.collectedPaise;
    } else {
      old += v.collectedPaise;
    }
    switch (v.mode) {
      case PaymentMode.cash:
        cash += v.collectedPaise;
      case PaymentMode.upi:
        upi += v.collectedPaise;
      case PaymentMode.cheque:
        cheque += v.collectedPaise;
      case PaymentMode.credit:
        break;
    }
    if (e.latest.sequence > version) version = e.latest.sequence;
  }
  return SettlementTotals(
    bills: bills,
    oldPayments: old,
    cash: cash,
    upi: upi,
    cheque: cheque,
    credit: credit,
    ledgerVersion: version,
  );
}

class SettlementCommand {
  const SettlementCommand({
    required this.operationId,
    required this.driverId,
    required this.date,
    required this.action,
    required this.expectedRevision,
    required this.ledgerVersion,
    required this.capturedAt,
    this.handedPaise = 0,
    this.reason = '',
  });
  final String operationId, driverId, date, reason;
  final SettlementAction action;
  final int expectedRevision, ledgerVersion, handedPaise;
  final DateTime capturedAt;
  void validate() {
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        dateKey(parsed) != date ||
        expectedRevision < 0 ||
        ledgerVersion < 0 ||
        handedPaise < 0 ||
        handedPaise > maxMoneyPaise ||
        reason.length > 500 ||
        (action == SettlementAction.reopen && reason.trim().isEmpty)) {
      throw const FormatException(
        'Enter a valid day, amount and reopening reason (up to 500 characters).',
      );
    }
  }

  Map<String, dynamic> toMap() => {
    'operation_id': operationId,
    'driver_id': driverId,
    'service_date': date,
    'action': action.name,
    'expected_revision': expectedRevision,
    'ledger_version': ledgerVersion,
    'handed_paise': handedPaise,
    'reason': reason.trim(),
    'captured_at': capturedAt.toUtc().toIso8601String(),
  };
  factory SettlementCommand.fromMap(Map<String, dynamic> m) =>
      SettlementCommand(
        operationId: m['operation_id'] as String,
        driverId: m['driver_id'] as String,
        date: m['service_date'] as String,
        action: SettlementAction.values.byName(m['action'] as String),
        expectedRevision: (m['expected_revision'] as num).toInt(),
        ledgerVersion: (m['ledger_version'] as num).toInt(),
        handedPaise: (m['handed_paise'] as num).toInt(),
        reason: m['reason'] as String,
        capturedAt: DateTime.parse(m['captured_at'] as String),
      );
}

class SettlementEvent {
  const SettlementEvent({
    required this.command,
    required this.actorId,
    required this.revision,
    required this.recordedAt,
    required this.totals,
  });
  final SettlementCommand command;
  final String actorId;
  final int revision;
  final DateTime recordedAt;
  final SettlementTotals totals;
  Map<String, dynamic> toMap() => {
    'payload': command.toMap(),
    'actor_id': actorId,
    'revision': revision,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'totals': totals.toMap(),
  };
  factory SettlementEvent.fromMap(Map<String, dynamic> m) => SettlementEvent(
    command: SettlementCommand.fromMap(
      Map<String, dynamic>.from(m['payload'] as Map),
    ),
    actorId: m['actor_id'] as String,
    revision: (m['revision'] as num).toInt(),
    recordedAt: DateTime.parse(m['recorded_at'] as String),
    totals: SettlementTotals.fromMap(
      Map<String, dynamic>.from(m['totals'] as Map),
    ),
  );
}

class SettlementDay {
  const SettlementDay({
    required this.driverId,
    required this.date,
    required this.totals,
    this.events = const [],
  });
  final String driverId, date;
  final SettlementTotals totals;
  final List<SettlementEvent> events;
  SettlementEvent? get latest => events.isEmpty
      ? null
      : events.reduce((a, b) => a.revision > b.revision ? a : b);
  int get revision => latest?.revision ?? 0;
  bool get locked =>
      latest != null && latest!.command.action != SettlementAction.reopen;
  String get status => switch (latest?.command.action) {
    SettlementAction.submit => 'Submitted',
    SettlementAction.approve => 'Approved',
    SettlementAction.reopen => 'Reopened',
    null => 'Open',
  };
  Map<String, dynamic> toMap() => {
    'driver_id': driverId,
    'service_date': date,
    'totals': totals.toMap(),
    'events': events.map((e) => e.toMap()).toList(),
  };
  factory SettlementDay.fromMap(Map<String, dynamic> m) => SettlementDay(
    driverId: m['driver_id'] as String,
    date: m['service_date'] as String,
    totals: SettlementTotals.fromMap(
      Map<String, dynamic>.from(m['totals'] as Map),
    ),
    events: (m['events'] as List)
        .map(
          (e) => SettlementEvent.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}

class PendingSettlement {
  const PendingSettlement(this.command, {this.error, this.rejected = false});
  final SettlementCommand command;
  final String? error;
  final bool rejected;
}
