import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'shop_directory.dart';

class DispatchCard extends StatelessWidget {
  const DispatchCard({super.key, required this.child, this.accent});
  final Widget child;
  final Color? accent;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xffe1e2e8)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0500236f),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Container(
      decoration: BoxDecoration(
        border: accent == null
            ? null
            : Border(left: BorderSide(color: accent!, width: 4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

class DispatchBadge extends StatelessWidget {
  const DispatchBadge(
    this.text, {
    super.key,
    this.color = DirectoryDesign.teal,
    this.icon,
  });
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class BillUploadPanel extends StatelessWidget {
  const BillUploadPanel({
    super.key,
    required this.onCamera,
    this.onGallery,
    this.busy = false,
    this.hasPhoto = false,
    this.shopName = '',
    this.showGallery = false,
  });
  final VoidCallback? onCamera, onGallery;
  final bool busy, hasPhoto, showGallery;
  final String shopName;
  @override
  Widget build(BuildContext context) => DispatchCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xffdce1ff),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.document_scanner_outlined,
                color: DirectoryDesign.navy,
                size: 23,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Bill Upload & Dispatch',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Scan a bill, match its shop and confirm the drop point.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: DirectoryDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            DispatchBadge(
              busy
                  ? 'Reading bill…'
                  : hasPhoto
                  ? 'Photo captured'
                  : 'Ready to scan',
              icon: busy
                  ? Icons.hourglass_top
                  : hasPhoto
                  ? Icons.receipt_long_outlined
                  : Icons.photo_camera_outlined,
              color: busy ? DirectoryDesign.navy : DirectoryDesign.teal,
            ),
          ],
        ),
        if (hasPhoto) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xfff2f4f6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 34,
                  color: DirectoryDesign.navy,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Captured bill',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shopName.isEmpty
                            ? 'Check or enter the shop name below.'
                            : 'Review the shop name below.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: DirectoryDesign.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 10),
          const Text(
            'Photograph the whole bill. Only the customer’s shop name is extracted.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: DirectoryDesign.muted,
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onCamera,
          style: FilledButton.styleFrom(
            backgroundColor: DirectoryDesign.navy,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.photo_camera_outlined, size: 20),
          label: Text(busy ? 'Reading shop name…' : 'Scan whole bill'),
        ),
        if (showGallery)
          TextButton.icon(
            onPressed: onGallery,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Choose a photo'),
          ),
      ],
    ),
  );
}

class DispatchDropPoint extends StatelessWidget {
  const DispatchDropPoint({super.key, required this.shop, this.onCall});
  final Shop shop;
  final VoidCallback? onCall;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfff2f4f6),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 17,
              color: DirectoryDesign.navy,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Drop point: ${shop.address.isNotEmpty ? shop.address : shop.area}',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
        if (shop.landmark.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              shop.landmark,
              style: const TextStyle(
                fontSize: 12,
                color: DirectoryDesign.muted,
              ),
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: Color(0xffe0e3e5)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.person_outline,
              size: 16,
              color: DirectoryDesign.muted,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                shop.contactName.isEmpty
                    ? 'Contact not added'
                    : 'Contact: ${shop.contactName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: DirectoryDesign.muted,
                ),
              ),
            ),
          ],
        ),
        if (shop.phone.isNotEmpty)
          TextButton.icon(
            onPressed: onCall,
            icon: const Icon(Icons.call_outlined, size: 16),
            label: Text(shop.phone),
          ),
      ],
    ),
  );
}

class OwnerDispatchBoard extends StatelessWidget {
  const OwnerDispatchBoard({
    super.key,
    required this.stops,
    required this.date,
    required this.onScan,
    required this.onAddStops,
    required this.onChooseDate,
    required this.onRefresh,
    required this.stopBuilder,
    this.busy = false,
  });
  final List<DeliveryStop> stops;
  final DateTime date;
  final VoidCallback onScan, onAddStops, onChooseDate;
  final Future<void> Function() onRefresh;
  final Widget Function(DeliveryStop, int) stopBuilder;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final pending = stops.where((s) => s.status == VisitStatus.pending).length;
    final delivered = stops
        .where((s) => s.status == VisitStatus.delivered)
        .length;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const Key('owner-dispatch-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BillUploadPanel(onCamera: busy ? null : onScan),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: busy ? null : onChooseDate,
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                        label: Text(readableDate(date)),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onAddStops,
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: Text(
                          stops.isEmpty ? 'Prepare delivery list' : 'Add stops',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.share_location_outlined,
                        size: 20,
                        color: DirectoryDesign.navy,
                      ),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Text(
                          'Shops & Route Assignment',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      DispatchBadge(
                        '$pending awaiting delivery',
                        icon: Icons.local_shipping_outlined,
                        color: DirectoryDesign.navy,
                      ),
                      DispatchBadge(
                        '$delivered delivered',
                        icon: Icons.task_alt,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          if (stops.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 110),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Icon(
                      Icons.route_outlined,
                      size: 42,
                      color: DirectoryDesign.navy,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No stops for this day',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Scan a bill or choose saved shops to prepare this delivery list.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: DirectoryDesign.muted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              sliver: SliverList.builder(
                itemCount: stops.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: stopBuilder(stops[index], index + 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
