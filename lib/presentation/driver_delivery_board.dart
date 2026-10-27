import 'package:flutter/material.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';
import '../domain/ledger.dart';
import 'dispatch_design.dart';
import 'shop_directory.dart';

/// Driver execution view. The controller supplies only this account's assigned
/// stops, already sorted by the owner's saved order.
class DriverDeliveryBoard extends StatelessWidget {
  const DriverDeliveryBoard({
    super.key,
    required this.controller,
    required this.date,
    required this.onChooseDate,
    required this.onNavigate,
    required this.onCall,
    required this.onShop,
    required this.onDelivered,
    required this.onFailed,
    required this.onReopen,
    required this.onLedger,
    required this.onCollection,
    required this.onSettlement,
  });
  final DeliveryController controller;
  final DateTime date;
  final VoidCallback onChooseDate, onSettlement;
  final ValueChanged<Shop> onNavigate, onCall, onShop, onLedger;
  final ValueChanged<DeliveryStop> onDelivered,
      onFailed,
      onReopen,
      onCollection;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final stops = c.stopsFor(date);
    final remaining = stops
        .where((s) => s.status == VisitStatus.pending)
        .toList();
    final delivered = stops
        .where((s) => s.status == VisitStatus.delivered)
        .length;
    final failed = stops.where((s) => s.status == VisitStatus.failed).length;
    final next = remaining.firstOrNull;
    final nextShop = next == null ? null : c.shopFor(next.shopId);
    final locked = c.isSettlementLocked(c.accountId, dateKey(date));
    final today = dateKey(date) == dateKey(DateTime.now());
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: CustomScrollView(
        key: const Key('driver-delivery-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'My deliveries',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Choose delivery date',
                        onPressed: c.busy ? null : onChooseDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                      ),
                      IconButton(
                        tooltip: 'Refresh deliveries',
                        onPressed: c.busy ? null : c.refresh,
                        icon: const Icon(Icons.sync),
                      ),
                    ],
                  ),
                  Text(
                    readableDate(date),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DirectoryDesign.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DispatchCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(
                              today
                                  ? 'Today’s delivery progress'
                                  : 'Delivery progress',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            DispatchBadge(
                              '${stops.isEmpty ? 0 : (delivered * 100 / stops.length).round()}% delivered',
                              icon: Icons.task_alt,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: stops.isEmpty ? 0 : delivered / stops.length,
                            minHeight: 7,
                            color: DirectoryDesign.teal,
                            backgroundColor: const Color(0xffeceef0),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _metric(
                              '$delivered',
                              'Delivered',
                              Icons.task_alt,
                              DirectoryDesign.teal,
                            ),
                            const SizedBox(width: 6),
                            _metric(
                              '${remaining.length}',
                              'Pending',
                              Icons.pending_actions,
                              DirectoryDesign.navy,
                            ),
                            const SizedBox(width: 6),
                            _metric(
                              '$failed',
                              'Not delivered',
                              Icons.report_gmailerrorred,
                              const Color(0xff995600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (next != null)
                    Container(
                      key: const Key('driver-route-overview'),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: DirectoryDesign.navy,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.alt_route,
                                color: Color(0xff89f5e7),
                                size: 19,
                              ),
                              SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  'OWNER’S DELIVERY ORDER',
                                  style: TextStyle(
                                    color: Color(0xff89f5e7),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .8,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.lock_outline,
                                color: Color(0xffdce1ff),
                                size: 16,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Next · Stop ${stops.indexOf(next) + 1}',
                            style: const TextStyle(
                              color: Color(0xffdce1ff),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            nextShop?.name ?? 'Shop details unavailable',
                            key: const Key('driver-next-shop'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (nextShop != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                nextShop.address.isNotEmpty
                                    ? nextShop.address
                                    : nextShop.area,
                                style: const TextStyle(
                                  color: Color(0xffdce1ff),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: remaining.length,
                              separatorBuilder: (_, _) => const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: Color(0xffb6c4ff),
                                ),
                              ),
                              itemBuilder: (context, index) {
                                final stop = remaining[index];
                                return Container(
                                  alignment: Alignment.center,
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: index == 0
                                        ? DirectoryDesign.teal
                                        : Colors.white.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '#${stops.indexOf(stop) + 1} ${c.shopFor(stop.shopId)?.name ?? 'Shop unavailable'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('driver-navigate-next'),
                            onPressed: nextShop?.readyForDelivery == true
                                ? () => onNavigate(nextShop!)
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: DirectoryDesign.navy,
                              disabledBackgroundColor: Colors.white24,
                              disabledForegroundColor: Colors.white70,
                              minimumSize: const Size(48, 48),
                            ),
                            icon: const Icon(
                              Icons.navigation_outlined,
                              size: 20,
                            ),
                            label: const Text('Navigate to next shop'),
                          ),
                          if (nextShop?.readyForDelivery != true)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Ask the owner to update this shop’s delivery location.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (next == null && stops.isNotEmpty)
                    DispatchCard(
                      accent: DirectoryDesign.teal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            failed == 0
                                ? Icons.verified_outlined
                                : Icons.fact_check_outlined,
                            color: DirectoryDesign.teal,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            failed == 0
                                ? 'All assigned stops delivered'
                                : 'All stops have a result',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (failed > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '$failed could not be delivered. Review the reasons with the owner.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: DirectoryDesign.muted,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: onSettlement,
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Daily settlement'),
                          ),
                        ],
                      ),
                    ),
                  if (locked)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'This day’s settlement is submitted or approved. Ask the owner to reopen it before recording changes.',
                        style: TextStyle(
                          color: Color(0xff995600),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      const Text(
                        'Assigned stops',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      DispatchBadge(
                        '${stops.length} stops · owner order',
                        color: DirectoryDesign.navy,
                        icon: Icons.format_list_numbered,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Follow the numbered stops. Directions open the saved shop location in Google Maps.',
                    style: TextStyle(
                      fontSize: 12,
                      color: DirectoryDesign.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (stops.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 26),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.local_shipping_outlined,
                            size: 42,
                            color: DirectoryDesign.navy,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No assigned deliveries',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'The owner’s assigned shops will appear here after syncing.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: c.busy ? null : c.refresh,
                            icon: const Icon(Icons.sync),
                            label: const Text('Check for deliveries'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList.builder(
              itemCount: stops.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _stop(
                  context,
                  stops[index],
                  index + 1,
                  stops[index].id == next?.id,
                  locked,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xfff2f4f6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: DirectoryDesign.muted,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _stop(
    BuildContext context,
    DeliveryStop stop,
    int number,
    bool next,
    bool locked,
  ) {
    final c = controller;
    final shop = c.shopFor(stop.shopId);
    final queued = c.pendingStopIds.contains(stop.id);
    final canChange = !c.busy && !queued && !locked && shop != null;
    return DispatchCard(
      key: ValueKey('driver-stop-${stop.id}'),
      accent: next ? DirectoryDesign.navy : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: next
                    ? DirectoryDesign.navy
                    : const Color(0xffeef0f5),
                foregroundColor: next ? Colors.white : DirectoryDesign.navy,
                child: stop.status == VisitStatus.delivered
                    ? const Icon(Icons.check, size: 18)
                    : Text(
                        '$number',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STOP $number${next ? ' · NEXT UP' : ''}',
                      style: TextStyle(
                        fontSize: 10,
                        color: next
                            ? DirectoryDesign.teal
                            : DirectoryDesign.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: shop == null ? null : () => onShop(shop),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          shop?.name ?? 'Shop details unavailable',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              DispatchBadge(
                queued ? 'Waiting to sync' : stop.status.label,
                color: queued || stop.status == VisitStatus.failed
                    ? const Color(0xff995600)
                    : DirectoryDesign.teal,
                icon: queued
                    ? Icons.cloud_upload_outlined
                    : stop.status == VisitStatus.delivered
                    ? Icons.task_alt
                    : Icons.schedule,
              ),
              if (shop != null)
                DispatchBadge(
                  shop.hasMapsLink
                      ? 'Maps link saved'
                      : shop.readyForDelivery
                      ? 'Verified entrance'
                      : 'Location needs update',
                  color: DirectoryDesign.navy,
                  icon: Icons.location_on_outlined,
                ),
            ],
          ),
          if (shop != null) ...[
            const SizedBox(height: 12),
            if (shop.contactName.isNotEmpty)
              Text(
                shop.contactName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (shop.phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  shop.phone,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DirectoryDesign.muted,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              shop.address.isNotEmpty ? shop.address : shop.area,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            if (shop.landmark.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Landmark: ${shop.landmark}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DirectoryDesign.muted,
                  ),
                ),
              ),
            if (shop.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  shop.notes,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Outstanding: ${rupees(c.balanceFor(shop.id).balancePaise)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: shop.phone.isEmpty ? null : () => onCall(shop),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call shop'),
                ),
                OutlinedButton.icon(
                  onPressed: shop.readyForDelivery
                      ? () => onNavigate(shop)
                      : null,
                  icon: const Icon(Icons.directions_outlined, size: 18),
                  label: const Text('Directions'),
                ),
              ],
            ),
            if (stop.status == VisitStatus.pending) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: ValueKey('driver-delivered-${stop.id}'),
                onPressed: canChange ? () => onDelivered(stop) : null,
                icon: const Icon(Icons.task_alt, size: 19),
                label: const Text('Delivered & collection'),
              ),
              TextButton.icon(
                key: ValueKey('driver-failed-${stop.id}'),
                onPressed: canChange ? () => onFailed(stop) : null,
                icon: const Icon(Icons.report_problem_outlined, size: 16),
                label: const Text('Could not deliver'),
              ),
            ],
            if (stop.status == VisitStatus.delivered)
              OutlinedButton.icon(
                onPressed: canChange ? () => onCollection(stop) : null,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Record collection'),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('More actions', style: TextStyle(fontSize: 12)),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => onLedger(shop),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Shop ledger'),
                    ),
                    if (stop.status != VisitStatus.pending)
                      TextButton(
                        onPressed: canChange ? () => onReopen(stop) : null,
                        child: const Text('Reopen delivery'),
                      ),
                    TextButton(
                      onPressed: () => onShop(shop),
                      child: const Text('Shop details'),
                    ),
                  ],
                ),
              ],
            ),
          ],
          if (stop.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Reason: ${stop.reason}',
                style: const TextStyle(color: Color(0xff995600), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
