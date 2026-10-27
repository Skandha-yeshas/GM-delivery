part of 'delivery_controller.dart';

extension CollectionsController on DeliveryController {
  Future<void> _importOpening(Shop shop, int amount) async {
    // Persist the exact request before queuing it, including the timestamp. A
    // retry after a process crash must reuse both the ID and identical payload.
    final id = const Uuid().v5(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
      'gm-opening:${shop.id}',
    );
    final known = [...await store.ledgerEntries()]
        .where(
          (e) =>
              e.command.shopId == shop.id &&
              e.command.kind == LedgerKind.opening,
        )
        .firstOrNull;
    if (known != null) return;
    if ((await store.ledgerQueue()).any((p) => p.command.operationId == id)) {
      return;
    }
    final key = 'import-opening-${shop.id}';
    final saved = await store.getSetting(key);
    final command = saved == null
        ? LedgerCommand(
            operationId: id,
            shopId: shop.id,
            kind: LedgerKind.opening,
            capturedAt: DateTime.now().toUtc(),
            billPaise: amount,
            note: 'Opening balance from Excel import',
          )
        : LedgerCommand.fromMap(jsonDecode(saved) as Map<String, dynamic>);
    if (command.billPaise != amount) {
      throw StateError(
        'The saved opening-balance request has a different amount. Review the shop ledger instead of importing a second balance.',
      );
    }
    if (saved == null) await store.setting(key, jsonEncode(command.toMap()));
    await store.queueLedger(PendingLedger(command, profile!.id));
    pendingLedger = await store.ledgerQueue();
    if (!shared) {
      final cached = await store.ledgerEntries();
      final entry = _projectEntry(
        command,
        profile!.id,
        cached,
        cached.fold<int>(0, (n, e) => e.sequence > n ? e.sequence : n) + 1,
      );
      await store.acknowledgeLedger(
        entry,
        calculateCreditBalance(shop.id, [...cached, entry]),
      );
    }
  }

  List<LedgerEntry> get projectedLedger =>
      _ledgerProjection ??= _buildProjectedLedger();
  List<LedgerEntry> _buildProjectedLedger() {
    final result = List<LedgerEntry>.of(ledger);
    var sequence = result.fold<int>(
      0,
      (n, e) => e.sequence > n ? e.sequence : n,
    );
    for (final p in pendingLedger) {
      if (result.any((e) => e.id == p.command.operationId)) continue;
      result.add(_projectEntry(p.command, p.actorId, result, ++sequence));
    }
    return result;
  }

  CreditBalance balanceFor(String shopId) => _balanceProjection.putIfAbsent(
    shopId,
    () => _calculateBalanceFor(shopId),
  );
  CreditBalance _calculateBalanceFor(String shopId) {
    if (!shared) return calculateCreditBalance(shopId, projectedLedger);
    final cached =
        creditBalances.where((b) => b.shopId == shopId).firstOrNull ??
        CreditBalance(shopId: shopId);
    final unsynced = projectedLedger
        .where((e) => e.command.shopId == shopId && !_ledgerIds.contains(e.id))
        .toList();
    final flag = unsynced
        .where((e) => e.command.kind == LedgerKind.flag)
        .lastOrNull;
    final balance =
        cached.balancePaise +
        unsynced.fold<int>(0, (n, e) => n + e.debitDelta - e.creditDelta);
    return CreditBalance(
      shopId: shopId,
      balancePaise: balance,
      version: cached.version,
      oldestUnpaidAt: balance > 0
          ? cached.oldestUnpaidAt ??
                unsynced
                    .where((e) => e.debitDelta > 0)
                    .firstOrNull
                    ?.command
                    .capturedAt
          : null,
      lastPaymentAt:
          unsynced
              .where((e) => e.creditDelta > 0)
              .lastOrNull
              ?.command
              .capturedAt ??
          cached.lastPaymentAt,
      collectNextVisit:
          flag?.command.collectNextVisit ?? cached.collectNextVisit,
      flagRevision: flag?.revision ?? cached.flagRevision,
    );
  }

  Future<void> submitLedger(LedgerCommand command) async {
    await _saveOnPhone(() => _queueCollection(command));
    _requestSync();
  }

  // Network synchronization never holds the local driver-action write lock.
  // SQLite transactions serialize snapshot replacement and queue insertion.
  Future<void> _saveOnPhone(Future<void> Function() action) async {
    if (_phoneWriting) {
      throw StateError('Wait for the current phone save to finish.');
    }
    _phoneWriting = true;
    _phoneIdle = Completer<void>();
    try {
      await action();
      await reloadLocal();
    } finally {
      _phoneWriting = false;
      _phoneIdle!.complete();
      _notifyLocalChange();
      _startRequestedSync();
    }
  }

  void _requestSync() {
    if (!shared) return;
    _refreshRequested = true;
    _startRequestedSync();
  }

  void _startRequestedSync() {
    if (!_refreshRequested || busy || _phoneWriting) return;
    _refreshRequested = false;
    unawaited(refresh());
  }

  Future<void> _queueCollection(LedgerCommand command) async {
    if (profile == null || (!isOwner && profile!.role != UserRole.driver)) {
      throw StateError('An app account is required.');
    }
    if (shopFor(command.shopId) == null) {
      throw StateError('Shop is unavailable.');
    }
    if (!isOwner &&
        ![LedgerKind.bill, LedgerKind.payment].contains(command.kind)) {
      throw StateError(
        'Only owners can change opening balances, corrections or reminders.',
      );
    }
    final entries = projectedLedger;
    final effective = effectiveLedger(
      entries.where((e) => e.command.shopId == command.shopId).toList(),
    );
    final original = effective
        .where((e) => e.original.id == command.originalId)
        .firstOrNull;
    if (command.kind == LedgerKind.correction &&
        (original == null ||
            original.latest.revision != command.expectedRevision)) {
      throw StateError(
        'This ledger entry changed. Reopen it before correcting.',
      );
    }
    command.validate(correctedKind: original?.original.command.kind);
    if (command.kind == LedgerKind.flag &&
        command.expectedRevision != balanceFor(command.shopId).flagRevision) {
      throw StateError('This reminder changed. Reopen the ledger.');
    }
    if (command.kind == LedgerKind.opening &&
        effective.any((e) => e.original.command.kind == LedgerKind.opening)) {
      throw StateError(
        'An opening balance already exists. Correct the original entry instead.',
      );
    }
    if ((command.kind == LedgerKind.bill ||
            original?.original.command.kind == LedgerKind.bill) &&
        effective.any(
          (e) =>
              e.original.command.kind == LedgerKind.bill &&
              e.original.id != command.originalId &&
              e.values.billNumber.trim().toLowerCase() ==
                  command.billNumber.trim().toLowerCase(),
        )) {
      throw StateError('This bill number is already recorded for the shop.');
    }
    if ([LedgerKind.bill, LedgerKind.payment].contains(command.kind)) {
      final stop = stops
          .where((s) => s.id == command.stopId && s.shopId == command.shopId)
          .firstOrNull;
      if (stop == null || (!isOwner && stop.driverId != accountId)) {
        throw StateError('This delivery is not assigned to you.');
      }
      if (pendingLedger.any(
        (p) =>
            p.command.stopId == stop.id &&
            p.command.legacyVisitOperationId != null,
      )) {
        throw StateError(
          'Sync the recovered collection before adding another record to this stop.',
        );
      }
      if (pending.any(
        (p) =>
            p.stopId == stop.id &&
            !(p.status == VisitStatus.delivered &&
                p.operationId == command.legacyVisitOperationId),
      )) {
        throw StateError(
          'Sync the pending delivery result before recording this collection.',
        );
      }
    }
    if (command.kind == LedgerKind.payment &&
        (shared && !creditBalances.any((b) => b.shopId == command.shopId) ||
            command.collectedPaise > balanceFor(command.shopId).balancePaise)) {
      throw StateError(
        'Payment exceeds the downloaded outstanding balance. Sync and review the shop ledger.',
      );
    }
    await store.queueLedger(PendingLedger(command, profile!.id));
    pendingLedger = await store.ledgerQueue();
    if (!shared) {
      for (final queued in pendingLedger) {
        final cached = await store.ledgerEntries();
        final entry = _projectEntry(
          queued.command,
          queued.actorId,
          cached,
          cached.fold<int>(0, (n, e) => e.sequence > n ? e.sequence : n) + 1,
        );
        await store.acknowledgeLedger(
          entry,
          calculateCreditBalance(command.shopId, [...cached, entry]),
        );
      }
    }
  }

  LedgerEntry _projectEntry(
    LedgerCommand command,
    String actor,
    List<LedgerEntry> entries,
    int sequence,
  ) {
    final previous = effectiveLedger(
      entries,
    ).where((e) => e.original.id == command.originalId).firstOrNull;
    final stop = stops.where((s) => s.id == command.stopId).firstOrNull;
    return LedgerEntry(
      command: command,
      actorId: actor,
      sequence: sequence,
      revision: [LedgerKind.correction, LedgerKind.flag].contains(command.kind)
          ? command.expectedRevision + 1
          : 1,
      debitDelta: command.billPaise - (previous?.values.billPaise ?? 0),
      creditDelta:
          command.collectedPaise - (previous?.values.collectedPaise ?? 0),
      recordedAt: DateTime.now().toUtc(),
      stopAfter:
          [LedgerKind.bill, LedgerKind.payment].contains(command.kind) &&
              stop != null
          ? DeliveryStop(
              id: stop.id,
              shopId: stop.shopId,
              date: stop.date,
              driverId: stop.driverId,
              order: stop.order,
              status: VisitStatus.delivered,
              version: command.expectedStopVersion! + 1,
            )
          : null,
    );
  }

  Future<void> _syncLedgerQueue() async {
    final blocked = <String>{};
    for (final queued in await store.ledgerQueue()) {
      if (blocked.contains(queued.command.shopId)) continue;
      try {
        final receipt = await cloud!.sendLedger(queued.command);
        await store.acknowledgeLedger(receipt.entry, receipt.balance);
      } catch (error) {
        final message = ledgerError(error);
        blocked.add(queued.command.shopId);
        await store.ledgerFailure(queued.command.operationId, message);
        ledgerSyncError ??= message;
      }
    }
  }
}

String ledgerError(Object error) {
  if (error.toString().contains('SETTLEMENT_LOCKED')) {
    return settlementError(error);
  }
  final raw = error.toString();
  if (raw.contains('PGRST202') ||
      raw.contains('42P01') ||
      raw.contains('PGRST205')) {
    return 'Collections database update needed: run supabase/migrations/20261016_collections_ledger.sql. Saved phone records are retained.';
  }
  const messages = {
    'COLLECTION_REQUIRED':
        'Complete the collection form for this delivered stop. Its older saved result has been kept.',
    'DUPLICATE_BILL':
        'This bill number already exists. An owner must review the queued record; it has not been discarded.',
    'OPENING_EXISTS':
        'An opening balance already exists. An owner must review the queued record.',
    'PAYMENT_EXCEEDS_BALANCE':
        'This payment exceeds the shared outstanding balance. An owner must review the queued record.',
    'VERSION_CONFLICT':
        'This entry changed on another phone. An owner must review the saved operation before retrying.',
    'OPERATION_MISMATCH':
        'This operation ID already belongs to different data. The local record is retained for review.',
  };
  for (final code in messages.keys) {
    if (raw.contains(code)) return messages[code]!;
  }
  return errorText(error);
}
