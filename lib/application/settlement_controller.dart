part of 'delivery_controller.dart';

extension SettlementsController on DeliveryController {
  SettlementDay settlementFor(String driverId, String date) {
    final cached = settlements
        .where((d) => d.driverId == driverId && d.date == date)
        .firstOrNull;
    if (shared && cached != null) return cached;
    return SettlementDay(
      driverId: driverId,
      date: date,
      totals: settlementTotals(projectedLedger, stops, driverId, date),
      events: cached?.events ?? [],
    );
  }

  bool isSettlementLocked(String driverId, String date) =>
      settlementFor(driverId, date).locked ||
      pendingSettlements.any(
        (p) =>
            p.command.driverId == driverId &&
            p.command.date == date &&
            !p.rejected,
      );

  List<String> get pendingOperationDetails => [
    for (final p in pending)
      '${shopFor(stops.where((s) => s.id == p.stopId).firstOrNull?.shopId ?? '')?.name ?? 'Delivery'}: ${p.status.name}${p.reason.isEmpty ? '' : ' — ${p.reason}'}\nVisit ID: ${p.operationId}',
    for (final p in pendingLedger)
      '${shopFor(p.command.shopId)?.name ?? 'Shop'}: ${p.command.kind.name}, ${rupees(p.command.collectedPaise)} collected\nLedger ID: ${p.command.operationId}${p.error == null ? '' : '\n${p.error}'}',
    for (final p in pendingSettlements)
      '${p.command.date}: ${p.command.action.name}${p.rejected ? ' rejected by server' : ' awaiting receipt'}\nSettlement ID: ${p.command.operationId}${p.error == null ? '' : '\n${p.error}'}',
  ];

  Future<void> saveSettlementDraft(
    String driverId,
    String date,
    String amount,
    String reason,
  ) => store.setting(
    'settlement-draft:$driverId:$date',
    jsonEncode({'amount': amount, 'reason': reason}),
  );

  Future<void> submitSettlement(SettlementCommand c) async {
    await _saveOnPhone(() async {
      c.validate();
      if (profile == null) throw StateError('Sign in first.');
      if (c.action == SettlementAction.submit) {
        if (isOwner ||
            accountId != c.driverId ||
            profile!.role != UserRole.driver) {
          throw StateError(
            'The delivery person must submit their own settlement.',
          );
        }
      } else {
        _requireOwner();
      }
      if (c.date.compareTo(dateKey(DateTime.now())) > 0) {
        throw StateError('Future days cannot be settled.');
      }
      final day = settlementFor(c.driverId, c.date);
      if (shared &&
          !settlements.any(
            (d) => d.driverId == c.driverId && d.date == c.date,
          )) {
        throw StateError(
          'Sync this delivery day before submitting a settlement.',
        );
      }
      if (c.expectedRevision != day.revision ||
          c.ledgerVersion != day.totals.ledgerVersion) {
        throw StateError('This day changed. Review the latest totals.');
      }
      final action = day.latest?.command.action;
      if (c.action == SettlementAction.submit) {
        if (day.locked) {
          throw StateError(
            'An owner must reopen this day before another submission.',
          );
        }
        if (c.handedPaise != day.totals.cash && c.reason.trim().isEmpty) {
          throw StateError('Explain the cash difference before submitting.');
        }
      } else if (c.action == SettlementAction.approve) {
        if (action != SettlementAction.submit ||
            c.handedPaise != day.latest!.command.handedPaise) {
          throw StateError('Review the submitted cash before approving.');
        }
      } else if (!day.locked) {
        throw StateError('Only a submitted or approved day can be reopened.');
      }
      await store.queueSettlement(c);
      if (!shared) {
        final event = SettlementEvent(
          command: c,
          actorId: profile!.id,
          revision: day.revision + 1,
          recordedAt: DateTime.now().toUtc(),
          totals: day.totals,
        );
        await store.acknowledgeSettlement(
          c.operationId,
          SettlementDay(
            driverId: c.driverId,
            date: c.date,
            totals: day.totals,
            events: [...day.events, event],
          ),
        );
      }
    });
    _requestSync();
  }

  Future<void> discardRejectedSettlement(String id) => _saveOnPhone(() async {
    await store.discardRejectedSettlement(id);
    settlementSyncError = null;
  });

  Future<void> _syncSettlementQueue() async {
    if ((await store.pendingVisits()).isNotEmpty ||
        (await store.ledgerQueue()).isNotEmpty) {
      return;
    }
    for (final p in await store.settlementQueue()) {
      if (p.rejected) continue;
      try {
        await store.acknowledgeSettlement(
          p.command.operationId,
          await cloud!.sendSettlement(p.command),
        );
      } catch (error) {
        // These monotonic revision/sequence conflicts prove this request could
        // never have committed. Network failures remain locked and retryable.
        final rejected =
            error is PostgrestException &&
            [
              'SETTLEMENT_VERSION_CONFLICT',
              'SETTLEMENT_DAY_CHANGED',
            ].contains(error.message);
        final message = settlementError(error);
        await store.settlementFailure(
          p.command.operationId,
          message,
          rejected: rejected,
        );
        settlementSyncError ??= message;
      }
    }
  }
}

String settlementError(Object error) {
  final text = error.toString();
  if (text.contains('SETTLEMENT_VERSION_CONFLICT') ||
      text.contains('SETTLEMENT_DAY_CHANGED')) {
    return 'The server rejected this request because the day changed. Sync, remove the rejected request and review the latest totals.';
  }
  if (text.contains('SETTLEMENT_LOCKED')) {
    return 'This day is locked. An owner must reopen its settlement before collections change.';
  }
  if (text.contains('DIFFERENCE_REASON_REQUIRED')) {
    return 'Explain the cash difference before submitting.';
  }
  if (error is PostgrestException &&
      ['PGRST202', '42P01', '42883'].contains(error.code)) {
    return 'Apply 20261017_daily_settlements.sql in Supabase, then sync again.';
  }
  return errorText(error);
}
