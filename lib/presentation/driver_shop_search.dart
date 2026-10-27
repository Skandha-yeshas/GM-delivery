import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'dispatch_design.dart';
import 'shop_directory.dart';

enum DriverShopFilter { all, today, ready, needsUpdate }

class DriverShopSearch extends StatefulWidget {
  const DriverShopSearch({
    super.key,
    required this.shops,
    required this.todayShopIds,
    required this.searchController,
    required this.search,
    required this.onSearch,
    required this.onOpen,
    required this.onCall,
    required this.onMap,
    required this.onRefresh,
    this.busy = false,
    this.scopeLabel = 'Assigned shops',
  });
  final List<Shop> shops;
  final Set<String> todayShopIds;
  final TextEditingController searchController;
  final String search, scopeLabel;
  final ValueChanged<String> onSearch;
  final ValueChanged<Shop> onOpen, onCall, onMap;
  final Future<void> Function() onRefresh;
  final bool busy;
  @override
  State<DriverShopSearch> createState() => _DriverShopSearchState();
}

class _DriverShopSearchState extends State<DriverShopSearch> {
  DriverShopFilter _filter = DriverShopFilter.all;
  String? _area;
  bool _descending = false;

  bool _matches(Shop shop) {
    final query = widget.search.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      shop.name,
      shop.contactName,
      shop.phone,
      shop.address,
      shop.area,
      shop.postalCode,
      shop.landmark,
      shop.notes,
    ].join(' ').toLowerCase();
    if (query.split(RegExp(r'\s+')).every(haystack.contains)) return true;
    final digits = query.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty &&
        RegExp(r'^[+\d\s().-]+$').hasMatch(query) &&
        shop.phone.replaceAll(RegExp(r'\D'), '').contains(digits);
  }

  bool _inFilter(Shop shop, DriverShopFilter filter) => switch (filter) {
    DriverShopFilter.all => true,
    DriverShopFilter.today => widget.todayShopIds.contains(shop.id),
    DriverShopFilter.ready => shop.readyForDelivery,
    DriverShopFilter.needsUpdate => !shop.readyForDelivery,
  };

  void _reset() {
    widget.searchController.clear();
    widget.onSearch('');
    setState(() {
      _filter = DriverShopFilter.all;
      _area = null;
      _descending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas =
        widget.shops
            .map((s) => s.area.trim())
            .where((a) => a.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selectedArea = areas.contains(_area) ? _area : null;
    final records =
        widget.shops
            .where(
              (s) =>
                  _matches(s) &&
                  _inFilter(s, _filter) &&
                  (selectedArea == null || s.area.trim() == selectedArea),
            )
            .toList()
          ..sort((a, b) {
            var result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            if (result == 0) {
              result = a.area.toLowerCase().compareTo(b.area.toLowerCase());
            }
            if (result == 0) result = a.id.compareTo(b.id);
            return _descending ? -result : result;
          });
    final filtered =
        widget.search.isNotEmpty ||
        _filter != DriverShopFilter.all ||
        selectedArea != null;
    final labels = {
      DriverShopFilter.all: 'All shops',
      DriverShopFilter.today: 'Today’s stops',
      DriverShopFilter.ready: 'Location ready',
      DriverShopFilter.needsUpdate: 'Needs update',
    };
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .7),
            child: SingleChildScrollView(
              key: const Key('driver-shop-header'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Shop search',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh shops',
                          onPressed: widget.busy ? null : widget.onRefresh,
                          icon: const Icon(Icons.sync),
                        ),
                      ],
                    ),
                    TextField(
                      key: const Key('driver-shop-search'),
                      controller: widget.searchController,
                      onChanged: widget.onSearch,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      decoration: InputDecoration(
                        hintText: 'Search shop, contact or street…',
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 22),
                        suffixIcon: widget.search.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear shop search',
                                onPressed: () {
                                  widget.searchController.clear();
                                  widget.onSearch('');
                                },
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  size: 19,
                                ),
                              ),
                        filled: true,
                        fillColor: const Color(0xffeceef0),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: DirectoryDesign.navy,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final entry in labels.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                key: ValueKey(
                                  'driver-shop-filter-${entry.key.name}',
                                ),
                                selected: _filter == entry.key,
                                showCheckmark: false,
                                selectedColor: DirectoryDesign.navy,
                                backgroundColor: Colors.white,
                                label: Text(
                                  '${entry.value} (${widget.shops.where((s) => _inFilter(s, entry.key)).length})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _filter == entry.key
                                        ? Colors.white
                                        : DirectoryDesign.muted,
                                  ),
                                ),
                                onSelected: (_) =>
                                    setState(() => _filter = entry.key),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.scopeLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: DirectoryDesign.muted,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          key: const Key('driver-shop-area'),
                          tooltip: 'Filter by area',
                          onSelected: (value) => setState(
                            () => _area = value.isEmpty ? null : value,
                          ),
                          itemBuilder: (_) => [
                            CheckedPopupMenuItem(
                              value: '',
                              checked: selectedArea == null,
                              child: const Text('All areas'),
                            ),
                            for (final area in areas)
                              CheckedPopupMenuItem(
                                value: area,
                                checked: selectedArea == area,
                                child: Text(area),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.filter_alt_outlined,
                                  size: 17,
                                  color: DirectoryDesign.navy,
                                ),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 110,
                                  ),
                                  child: Text(
                                    selectedArea ?? 'All areas',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: DirectoryDesign.navy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('driver-shop-sort'),
                          tooltip: _descending ? 'Sort A to Z' : 'Sort Z to A',
                          onPressed: () =>
                              setState(() => _descending = !_descending),
                          icon: Icon(
                            _descending ? Icons.north : Icons.south,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: CustomScrollView(
                key: const Key('driver-shop-results'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xff1e3a8a),
                                  DirectoryDesign.navy,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.travel_explore,
                                  size: 30,
                                  color: Color(0xff89f5e7),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Find a shop on the go',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Search saved contacts and delivery locations. ${widget.shops.length} ${widget.shops.length == 1 ? 'shop available' : 'shops available'}.',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.5,
                                          color: Color(0xffdce1ff),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${records.length} ${records.length == 1 ? 'shop shown' : 'shops shown'}',
                                  key: const Key('driver-shop-count'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (filtered)
                                TextButton(
                                  onPressed: _reset,
                                  child: const Text('Reset filters'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (records.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.search_off,
                              size: 40,
                              color: DirectoryDesign.navy,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.shops.isEmpty
                                  ? 'No shops downloaded yet'
                                  : 'No matching shops',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.shops.isEmpty
                                  ? 'Sync after the owner assigns deliveries to your account.'
                                  : 'Try another name, contact, phone number or area.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: widget.shops.isEmpty
                                  ? (widget.busy ? null : widget.onRefresh)
                                  : _reset,
                              icon: Icon(
                                widget.shops.isEmpty
                                    ? Icons.sync
                                    : Icons.restart_alt,
                              ),
                              label: Text(
                                widget.shops.isEmpty
                                    ? 'Sync shops'
                                    : 'Reset search',
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: records.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _card(records[index]),
                        ),
                      ),
                    ),
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverToBoxAdapter(
                      child: DispatchCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 22,
                              color: DirectoryDesign.navy,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'The owner manages shop details and delivery assignments. Searching or opening a map does not change your delivery order.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DirectoryDesign.muted,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Shop shop) => DispatchCard(
    key: ValueKey('driver-search-shop-${shop.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xffeceef0),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.storefront_outlined,
                color: DirectoryDesign.navy,
                size: 23,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => widget.onOpen(shop),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shop.contactName.isEmpty
                          ? 'Contact not added'
                          : shop.contactName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DirectoryDesign.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xfff2f4f6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 17,
                color: DirectoryDesign.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  shop.address.isEmpty ? shop.area : shop.address,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            DispatchBadge(
              shop.hasMapsLink
                  ? 'Maps link saved'
                  : shop.readyForDelivery
                  ? 'Verified entrance'
                  : 'Location needs update',
              icon: Icons.pin_drop_outlined,
              color: shop.readyForDelivery
                  ? DirectoryDesign.teal
                  : const Color(0xff995600),
            ),
            if (widget.todayShopIds.contains(shop.id))
              const DispatchBadge(
                'Assigned today',
                icon: Icons.local_shipping_outlined,
                color: DirectoryDesign.navy,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: ValueKey('driver-search-call-${shop.id}'),
              onPressed: shop.phone.trim().isEmpty
                  ? null
                  : () => widget.onCall(shop),
              icon: const Icon(Icons.call_outlined, size: 17),
              label: const Text('Call shop'),
            ),
            FilledButton.icon(
              key: ValueKey('driver-search-map-${shop.id}'),
              onPressed: () => widget.onMap(shop),
              icon: const Icon(Icons.near_me_outlined, size: 17),
              label: const Text('View on map'),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<void> showDriverShopLocation(
  BuildContext context,
  Shop shop, {
  required ValueChanged<Shop> onNavigate,
  required ValueChanged<Shop> onCall,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.white,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Theme(
    data: DirectoryDesign.theme(Theme.of(context)),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shop.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close shop location',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xffeef1fc),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 40,
                    color: DirectoryDesign.navy,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    shop.locationDescription,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: DirectoryDesign.navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    shop.address.isEmpty ? shop.area : shop.address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            if (shop.landmark.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Landmark: ${shop.landmark}'),
              ),
            if (shop.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(shop.notes),
              ),
            if (shop.contactName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Contact: ${shop.contactName}'),
              ),
            if (!shop.readyForDelivery)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Ask the owner to add a Maps link or verify the entrance location.',
                  style: TextStyle(color: Color(0xff995600)),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('driver-search-open-maps'),
              onPressed: shop.readyForDelivery ? () => onNavigate(shop) : null,
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Open in Google Maps'),
            ),
            if (shop.phone.trim().isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => onCall(shop),
                icon: const Icon(Icons.call_outlined),
                label: Text('Call ${shop.phone}'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    ),
  ),
);
