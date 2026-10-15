import 'package:flutter/material.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';
import 'workspace_design.dart';

class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({
    super.key,
    required this.controller,
    required this.onScan,
    required this.onShops,
    required this.onReadyLocations,
    required this.onDeliveries,
    required this.onAddShop,
    required this.onImport,
    required this.onMissingLocations,
  });
  final DeliveryController controller;
  final VoidCallback onScan,
      onShops,
      onReadyLocations,
      onDeliveries,
      onAddShop,
      onImport,
      onMissingLocations;

  @override
  Widget build(BuildContext context) {
    final today = controller.stopsFor(DateTime.now());
    final completed = today
        .where((s) => s.status == VisitStatus.delivered)
        .length;
    final pending = today.where((s) => s.status == VisitStatus.pending).length;
    final ready = controller.shops.where((s) => s.readyForDelivery).length;
    final missing = controller.shops.length - ready;
    final next = today
        .where((s) => s.status == VisitStatus.pending)
        .take(3)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const WorkspaceLabel('Business overview'),
            Text(
              readableDate(DateTime.now()),
              style: const TextStyle(
                color: WorkspaceColors.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Welcome, ${controller.profile?.name ?? 'Owner'}',
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
            color: WorkspaceColors.ink,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xff15283f), Color(0xff23425c)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WorkspaceLabel(
                'Today’s operations',
                color: Color(0xff9ddbd0),
              ),
              const SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${today.length}',
                    style: const TextStyle(
                      fontSize: 52,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 10, bottom: 5),
                      child: Text(
                        'scheduled stops',
                        style: TextStyle(
                          color: Color(0xffcfdae6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.route_rounded,
                    color: Color(0xff9ddbd0),
                    size: 38,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                '$pending pending  ·  $completed delivered',
                style: const TextStyle(color: Color(0xffc2cfdd), fontSize: 13),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: controller.busy ? null : onScan,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff6de0c4),
                    foregroundColor: WorkspaceColors.ink,
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan shop name'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _metric(
                Icons.storefront_outlined,
                '${controller.shops.length}',
                'Total shops',
                onShops,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metric(
                Icons.verified_outlined,
                '$ready',
                'Ready locations',
                onReadyLocations,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const WorkspaceLabel('Quick actions'),
        const SizedBox(height: 12),
        WorkspaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _action(
                Icons.add_business_outlined,
                'Add a new shop',
                'Save a name, contact and entrance pin',
                onAddShop,
              ),
              const Divider(height: 1, indent: 66, endIndent: 18),
              _action(
                Icons.table_chart_outlined,
                'Import your shop list',
                'Bring shops from an Excel file',
                onImport,
              ),
            ],
          ),
        ),
        if (missing > 0) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: onMissingLocations,
            borderRadius: BorderRadius.circular(24),
            child: WorkspaceCard(
              color: const Color(0xfffff8e9),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_searching_rounded,
                    color: WorkspaceColors.amber,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$missing locations to complete',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: WorkspaceColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add a pin or verify the entrance.',
                          style: TextStyle(
                            fontSize: 12,
                            color: WorkspaceColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: WorkspaceColors.amber,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: WorkspaceLabel('Delivery queue')),
            TextButton(onPressed: onDeliveries, child: const Text('View list')),
          ],
        ),
        WorkspaceCard(
          child: next.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ready for the next delivery',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: WorkspaceColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Scan a shop name to prepare today’s list.',
                      style: TextStyle(
                        color: WorkspaceColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (var i = 0; i < next.length; i++) ...[
                      if (i > 0) const Divider(height: 24),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xffe8f5f1),
                            child: Text(
                              '${next[i].order}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: WorkspaceColors.teal,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.shopFor(next[i].shopId)?.name ??
                                      'Shop unavailable',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  controller.shopFor(next[i].shopId)?.area ??
                                      '',
                                  style: const TextStyle(
                                    color: WorkspaceColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: WorkspaceColors.muted,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _metric(
    IconData icon,
    String value,
    String title,
    VoidCallback action,
  ) => InkWell(
    onTap: action,
    borderRadius: BorderRadius.circular(24),
    child: WorkspaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: WorkspaceColors.teal, size: 22),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: WorkspaceColors.ink,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: WorkspaceColors.muted),
          ),
        ],
      ),
    ),
  );

  Widget _action(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => ListTile(
    onTap: action,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    leading: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xffeef3f8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: WorkspaceColors.ink, size: 22),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(fontSize: 11, color: WorkspaceColors.muted),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
  );
}
