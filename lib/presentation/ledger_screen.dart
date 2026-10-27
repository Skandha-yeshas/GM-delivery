import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../application/delivery_controller.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import 'collection_form.dart';
import 'common.dart';

void openShopLedger(
  BuildContext context,
  DeliveryController controller,
  String shopId,
) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ShopLedgerScreen(controller: controller, shopId: shopId),
  ),
);

class ShopLedgerScreen extends StatelessWidget {
  const ShopLedgerScreen({
    super.key,
    required this.controller,
    required this.shopId,
  });
  final DeliveryController controller;
  final String shopId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, shop = c.shopFor(shopId);
      if (shop == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Shop unavailable')),
          body: const Center(child: Text('Sync your assigned shops.')),
        );
      }
      final balance = c.balanceFor(shopId);
      final events =
          c.projectedLedger.where((e) => e.command.shopId == shopId).toList()
            ..sort((a, b) => a.sequence.compareTo(b.sequence));
      final effective = effectiveLedger(events);
      final stop =
          (c.stops
                  .where(
                    (s) =>
                        s.shopId == shopId &&
                        (c.isOwner || s.driverId == c.accountId),
                  )
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date)))
              .firstOrNull;
      var running = 0;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Shop ledger'),
          actions: [
            if (c.shared)
              IconButton(
                tooltip: 'Sync ledger',
                onPressed: c.busy ? null : c.refresh,
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          children: [
            Text(
              shop.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              balance.balancePaise < 0 ? 'Credit available' : 'Outstanding',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              rupees(balance.balancePaise.abs()),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            Text(
              'Last payment: ${balance.lastPaymentAt == null ? 'None recorded' : readableDate(balance.lastPaymentAt!.toLocal())}',
              style: const TextStyle(fontSize: 16),
            ),
            if (c.shared)
              const Text(
                'Downloaded balance plus phone entries waiting to sync. Refresh before relying on the final shared balance.',
              ),
            if (c.ledgerSyncError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  c.ledgerSyncError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (c.isOwner) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: balance.collectNextVisit,
                title: const Text('Collect on next visit'),
                subtitle: const Text(
                  'Preselect this shop when preparing the next delivery list. It stays flagged until an owner clears it.',
                ),
                onChanged: c.busy
                    ? null
                    : (value) => runAction(
                        context,
                        () => c.submitLedger(
                          LedgerCommand(
                            operationId: const Uuid().v4(),
                            shopId: shopId,
                            kind: LedgerKind.flag,
                            capturedAt: DateTime.now().toUtc(),
                            expectedRevision: balance.flagRevision,
                            collectNextVisit: value,
                          ),
                        ),
                      ),
              ),
              if (!effective.any(
                (e) => e.original.command.kind == LedgerKind.opening,
              ))
                OutlinedButton.icon(
                  onPressed: c.busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CollectionForm(
                              controller: c,
                              shopId: shopId,
                              kind: LedgerKind.opening,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Add opening balance'),
                ),
            ],
            if (stop != null)
              FilledButton.icon(
                onPressed: c.busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CollectionForm(
                            controller: c,
                            shopId: shopId,
                            stopId: stop.id,
                            kind: LedgerKind.payment,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record old-balance payment'),
              ),
            const SizedBox(height: 20),
            Text(
              c.isOwner
                  ? 'Bills, payments & audit history'
                  : 'Your collection records',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No ledger entries recorded yet.',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            for (final entry in events)
              if (entry.command.kind != LedgerKind.flag)
                Builder(
                  builder: (context) {
                    running += entry.debitDelta - entry.creditDelta;
                    final p = entry.command;
                    final current = effective
                        .where((e) => e.original.id == entry.id)
                        .firstOrNull;
                    final waiting = c.pendingLedger.any(
                      (q) => q.command.operationId == entry.id,
                    );
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.kind == LedgerKind.bill
                                  ? 'Bill ${p.billNumber}'
                                  : p.kind == LedgerKind.payment
                                  ? 'Payment'
                                  : p.kind == LedgerKind.opening
                                  ? 'Opening balance'
                                  : 'Correction · revision ${entry.revision}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${readableDate(p.capturedAt.toLocal())} · ${waiting ? 'Waiting to sync' : 'Saved'}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (p.kind == LedgerKind.correction) ...[
                              Text(
                                'Original: ${p.originalId}',
                                style: const TextStyle(fontSize: 16),
                              ),
                              Text(
                                'Reason: ${p.reason}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                            Text(
                              'Bill / opening: ${rupees(p.billPaise)}\nCollected: ${rupees(p.collectedPaise)} · ${p.mode.name.toUpperCase()}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (p.kind == LedgerKind.correction)
                              Text(
                                'Balance adjustment: ${rupees(entry.debitDelta - entry.creditDelta)}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            if (c.isOwner)
                              Text(
                                'Running balance: ${rupees(running)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (p.reference.isNotEmpty)
                              Text(
                                'Reference: ${p.reference}',
                                style: const TextStyle(fontSize: 16),
                              ),
                            if (p.note.isNotEmpty)
                              Text(
                                p.note,
                                style: const TextStyle(fontSize: 16),
                              ),
                            Text(
                              'GPS: ${p.location.status}${p.location.status == 'available' ? ' · ${p.location.latitude}, ${p.location.longitude} · ${p.location.accuracy!.round()} m' : ''}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              'Recorded by ${c.profiles.where((a) => a.id == entry.actorId).firstOrNull?.name ?? entry.actorId}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (c.isOwner && current != null)
                              TextButton.icon(
                                onPressed: c.busy
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CollectionForm(
                                            controller: c,
                                            shopId: shopId,
                                            kind: LedgerKind.correction,
                                            correction: current,
                                          ),
                                        ),
                                      ),
                                icon: const Icon(Icons.history),
                                label: Text(
                                  current.latest.revision > 1
                                      ? 'Correct latest values (v${current.latest.revision})'
                                      : 'Correct entry',
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ],
        ),
      );
    },
  );
}

class OutstandingScreen extends StatefulWidget {
  const OutstandingScreen({super.key, required this.controller});
  final DeliveryController controller;
  @override
  State<OutstandingScreen> createState() => _OutstandingScreenState();
}

class _OutstandingScreenState extends State<OutstandingScreen> {
  String? _area;
  bool _byAge = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.isOwner) {
        return const Scaffold(
          body: Center(
            child: Text('Only owners can view the outstanding directory.'),
          ),
        );
      }
      final areas = c.shops.map((s) => s.area).toSet().toList()..sort();
      final rows =
          c.shops
              .where(
                (s) =>
                    (_area == null || s.area == _area) &&
                    c.balanceFor(s.id).balancePaise > 0,
              )
              .toList()
            ..sort((a, b) {
              final left = c.balanceFor(a.id), right = c.balanceFor(b.id);
              if (_byAge) {
                return (left.oldestUnpaidAt ?? DateTime.now()).compareTo(
                  right.oldestUnpaidAt ?? DateTime.now(),
                );
              }
              return right.balancePaise.compareTo(left.balancePaise);
            });
      return Scaffold(
        appBar: AppBar(
          title: const Text('Outstanding balances'),
          actions: [
            if (c.shared)
              IconButton(
                tooltip: 'Sync collections',
                onPressed: c.busy ? null : c.refresh,
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Total: ${rupees(rows.fold<int>(0, (sum, s) => sum + c.balanceFor(s.id).balancePaise))}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (c.pendingLedger.isNotEmpty)
                    Text(
                      '${c.pendingLedger.length} financial operation(s) waiting to sync.',
                      style: const TextStyle(fontSize: 16),
                    ),
                  if (c.ledgerSyncError != null) Text(c.ledgerSyncError!),
                  DropdownButtonFormField<String>(
                    initialValue: _area,
                    decoration: const InputDecoration(labelText: 'Area'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All areas'),
                      ),
                      for (final area in areas)
                        DropdownMenuItem(value: area, child: Text(area)),
                    ],
                    onChanged: (value) => setState(() => _area = value),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Largest amount'),
                      ),
                      ButtonSegment(value: true, label: Text('Oldest first')),
                    ],
                    selected: {_byAge},
                    onSelectionChanged: (values) =>
                        setState(() => _byAge = values.single),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'No outstanding shops in this area.',
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final shop = rows[index], b = c.balanceFor(shop.id);
                        final age = b.oldestUnpaidAt == null
                            ? null
                            : DateTime.now()
                                  .difference(b.oldestUnpaidAt!)
                                  .inDays
                                  .clamp(0, 100000);
                        return ListTile(
                          title: Text(
                            '${shop.name} · ${rupees(b.balancePaise)}',
                          ),
                          subtitle: Text(
                            '${shop.area} · ${age == null ? 'Age not downloaded' : '$age days'}${b.collectNextVisit ? '\nCollect on next visit' : ''}',
                          ),
                          onTap: () => openShopLedger(context, c, shop.id),
                          trailing: shop.phone.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Call ${shop.name}',
                                  onPressed: () => callShop(context, shop),
                                  icon: const Icon(Icons.call_outlined),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class CollectionQueueScreen extends StatelessWidget {
  const CollectionQueueScreen({super.key, required this.controller});
  final DeliveryController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Collection sync queue')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Financial records stay on this phone until the server acknowledges them. A failed record also holds later records for the same shop. Sync again after an owner resolves the shared conflict.',
            style: TextStyle(fontSize: 16),
          ),
          FilledButton.icon(
            onPressed: controller.busy ? null : controller.refresh,
            icon: const Icon(Icons.sync),
            label: const Text('Retry sync'),
          ),
          for (final pending in controller.pendingLedger)
            ListTile(
              title: Text(
                '${controller.shopFor(pending.command.shopId)?.name ?? pending.command.shopId} · ${pending.command.kind.name}',
              ),
              subtitle: Text(
                'Operation: ${pending.command.operationId}\nBill: ${rupees(pending.command.billPaise)} · collected: ${rupees(pending.command.collectedPaise)}\n${pending.error ?? 'Waiting to sync'}',
              ),
            ),
          if (controller.pendingLedger.isEmpty)
            const Text('No financial operations waiting to sync.'),
        ],
      ),
    ),
  );
}
