import 'package:flutter/material.dart';
import '../domain/models.dart';

abstract final class DirectoryDesign {
  static const navy = Color(0xff00236f);
  static const teal = Color(0xff006a61);
  static const surface = Color(0xfff7f9fb);
  static const muted = Color(0xff444651);

  static ThemeData theme(ThemeData base) => base.copyWith(
    scaffoldBackgroundColor: surface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: navy,
      primary: navy,
      secondary: teal,
      surface: surface,
      onSurface: const Color(0xff191c1e),
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'PlusJakartaSans',
      bodyColor: const Color(0xff191c1e),
      displayColor: const Color(0xff191c1e),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: navy,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: Color(0xffdce1ff),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) =>
            (base.navigationBarTheme.labelTextStyle?.resolve(states) ??
                    base.textTheme.labelMedium!)
                .copyWith(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: states.contains(WidgetState.selected) ? navy : muted,
                ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? navy : muted,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: navy,
      foregroundColor: Colors.white,
      shape: const StadiumBorder(),
      extendedTextStyle:
          (base.floatingActionButtonTheme.extendedTextStyle ??
                  base.textTheme.labelLarge!)
              .copyWith(
                fontFamily: 'PlusJakartaSans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: navy,
        textStyle: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xfff2f4f6),
      selectedColor: navy,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
  );
}

/// Directory presentation only. Shop persistence and delivery rules stay in the controller.
class ShopDirectory extends StatefulWidget {
  const ShopDirectory({
    super.key,
    required this.shops,
    required this.search,
    required this.searchController,
    required this.onSearch,
    required this.area,
    required this.onArea,
    required this.locationFilter,
    required this.onLocationFilter,
    required this.isOwner,
    required this.busy,
    required this.onImport,
    required this.onAdd,
    required this.onOpen,
    required this.onCall,
    required this.onRefresh,
  });

  final List<Shop> shops;
  final String search, locationFilter;
  final String? area;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch, onLocationFilter;
  final ValueChanged<String?> onArea;
  final bool isOwner, busy;
  final VoidCallback onImport, onAdd;
  final ValueChanged<Shop> onOpen, onCall;
  final Future<void> Function() onRefresh;

  @override
  State<ShopDirectory> createState() => _ShopDirectoryState();
}

class _ShopDirectoryState extends State<ShopDirectory> {
  String _letters = 'All';
  bool _descending = false;
  static const _ranges = ['All', 'A–D', 'E–K', 'L–R', 'S–Z'];
  static const _locations = [
    'All locations',
    'Needs attention',
    'Needs location',
    'Needs verification',
    'Ready for delivery',
  ];

  String _initial(Shop shop) {
    final name = shop.name.trim().toUpperCase();
    return name.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(name) ? name[0] : '#';
  }

  bool _inRange(Shop shop) {
    if (_letters == 'All') return true;
    final initial = _initial(shop);
    return initial.compareTo(_letters[0]) >= 0 &&
        initial.compareTo(_letters[_letters.length - 1]) <= 0;
  }

  void _reset() {
    widget.searchController.clear();
    widget.onSearch('');
    widget.onArea(null);
    widget.onLocationFilter('All locations');
    setState(() {
      _letters = 'All';
      _descending = false;
    });
  }

  Widget _pill(String text, {Color color = DirectoryDesign.muted}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );

  Widget _controls(int shown) {
    final areas = widget.shops.map((s) => s.area).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('directory-search'),
          controller: widget.searchController,
          onChanged: widget.onSearch,
          decoration: InputDecoration(
            hintText: 'Search shop name or street address…',
            hintStyle: const TextStyle(
              fontSize: 13,
              color: DirectoryDesign.muted,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: DirectoryDesign.muted,
              size: 22,
            ),
            suffixIcon: widget.search.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      widget.searchController.clear();
                      widget.onSearch('');
                    },
                    icon: const Icon(Icons.close, size: 18),
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
              borderSide: const BorderSide(color: DirectoryDesign.navy),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final range in _ranges)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('directory-range-$range'),
                    avatar: _letters == range
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : null,
                    label: Text(
                      range == 'All' ? 'All (${widget.shops.length})' : range,
                      style: TextStyle(
                        fontSize: 12,
                        color: _letters == range
                            ? Colors.white
                            : DirectoryDesign.muted,
                      ),
                    ),
                    selected: _letters == range,
                    onSelected: (_) => setState(() => _letters = range),
                  ),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<String>(
              key: const Key('directory-location-filter'),
              tooltip: 'Filter by delivery location',
              initialValue: widget.locationFilter,
              onSelected: widget.onLocationFilter,
              itemBuilder: (_) => [
                for (final value in _locations)
                  CheckedPopupMenuItem(
                    value: value,
                    checked: value == widget.locationFilter,
                    child: Text(value),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.tune,
                      size: 16,
                      color: DirectoryDesign.navy,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.locationFilter,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DirectoryDesign.navy,
                      ),
                    ),
                    const Icon(
                      Icons.expand_more,
                      size: 16,
                      color: DirectoryDesign.navy,
                    ),
                  ],
                ),
              ),
            ),
            if (areas.isNotEmpty)
              PopupMenuButton<String>(
                key: const Key('directory-area-filter'),
                tooltip: 'Filter by area',
                onSelected: (value) =>
                    widget.onArea(value.isEmpty ? null : value),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('All areas')),
                  for (final area in areas)
                    PopupMenuItem(value: area, child: Text(area)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        size: 16,
                        color: DirectoryDesign.navy,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          widget.area ?? 'All areas',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: DirectoryDesign.navy,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        size: 16,
                        color: DirectoryDesign.navy,
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.isOwner)
              TextButton.icon(
                onPressed: widget.busy ? null : widget.onImport,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Import Excel'),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Container(
              width: 112,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        size: 18,
                        color: DirectoryDesign.navy,
                      ),
                      Icon(Icons.circle, size: 7, color: DirectoryDesign.teal),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.shops.length}',
                    key: const Key('directory-registered-count'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'Registered',
                    style: TextStyle(
                      fontSize: 11,
                      color: DirectoryDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$shown ${shown == 1 ? 'shop' : 'shops'} shown',
                key: const Key('directory-result-count'),
                style: const TextStyle(
                  fontSize: 12,
                  color: DirectoryDesign.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wholesale Retailers Directory',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  _pill(_descending ? 'Z–A' : 'A–Z'),
                ],
              ),
            ),
            TextButton.icon(
              key: const Key('directory-sort'),
              onPressed: () => setState(() => _descending = !_descending),
              icon: Icon(
                _descending ? Icons.south : Icons.sort_by_alpha,
                size: 16,
              ),
              label: Text(_descending ? 'Reverse' : 'Sorted'),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _group(String letter, int count) => Padding(
    key: ValueKey('directory-group-$letter'),
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Row(
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: DirectoryDesign.navy,
            shape: BoxShape.circle,
          ),
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: Color(0xffe0e3e5), thickness: 2)),
        const SizedBox(width: 8),
        Text(
          '$count ${count == 1 ? 'Retailer' : 'Retailers'}',
          style: const TextStyle(fontSize: 11, color: DirectoryDesign.muted),
        ),
      ],
    ),
  );

  Widget _shop(Shop shop) {
    final phone = shop.phone.trim();
    final address = [shop.address, shop.landmark, shop.area].firstWhere(
      (value) => value.trim().isNotEmpty && value != 'Area not set',
      orElse: () => 'Address not added',
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: ValueKey('directory-shop-${shop.id}'),
        color: Colors.white,
        elevation: .5,
        shadowColor: DirectoryDesign.navy.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpen(shop),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
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
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.person_outline,
                                size: 16,
                                color: DirectoryDesign.navy,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  shop.contactName.isEmpty
                                      ? 'Contact not added'
                                      : shop.contactName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: DirectoryDesign.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: DirectoryDesign.teal,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  address,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: DirectoryDesign.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: ValueKey('directory-call-${shop.id}'),
                      tooltip: phone.isEmpty
                          ? 'Phone not added'
                          : 'Call ${shop.name}',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xffe0f3ef),
                        foregroundColor: DirectoryDesign.teal,
                      ),
                      onPressed: phone.isEmpty
                          ? null
                          : () => widget.onCall(shop),
                      icon: const Icon(Icons.call_outlined, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xffeceef0)),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (phone.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Phone not added',
                          style: TextStyle(
                            fontSize: 12,
                            color: DirectoryDesign.muted,
                          ),
                        ),
                      )
                    else
                      TextButton.icon(
                        key: ValueKey('directory-phone-${shop.id}'),
                        onPressed: () => widget.onCall(shop),
                        icon: const Icon(
                          Icons.phone_in_talk_outlined,
                          size: 16,
                        ),
                        label: Text(phone),
                      ),
                    _pill(
                      shop.locationStatus,
                      color: shop.readyForDelivery
                          ? DirectoryDesign.teal
                          : const Color(0xffa66b12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.search.trim().toLowerCase();
    final matching =
        widget.shops
            .where(
              (shop) =>
                  (widget.area == null || shop.area == widget.area) &&
                  (widget.locationFilter == 'All locations' ||
                      (widget.locationFilter == 'Needs attention' &&
                          !shop.readyForDelivery) ||
                      shop.locationStatus == widget.locationFilter) &&
                  _inRange(shop) &&
                  '${shop.name} ${shop.area} ${shop.address} ${shop.landmark} ${shop.phone} ${shop.contactName} ${shop.postalCode}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList()
          ..sort((a, b) {
            var order = _initial(a).compareTo(_initial(b));
            if (order == 0) {
              order = a.name.trim().toLowerCase().compareTo(
                b.name.trim().toLowerCase(),
              );
            }
            if (order == 0) order = a.id.compareTo(b.id);
            return _descending ? -order : order;
          });
    final counts = <String, int>{};
    for (final shop in matching) {
      counts.update(_initial(shop), (n) => n + 1, ifAbsent: () => 1);
    }
    final rows = <Object>[];
    String? previous;
    for (final shop in matching) {
      final letter = _initial(shop);
      if (letter != previous) {
        rows.add(letter);
        previous = letter;
      }
      rows.add(shop);
    }
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        key: const Key('shop-directory-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(child: _controls(matching.length)),
          ),
          if (rows.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return row is Shop
                      ? _shop(row)
                      : _group(row as String, counts[row]!);
                },
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      size: 44,
                      color: DirectoryDesign.teal,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.shops.isEmpty
                          ? 'Your shop directory starts here'
                          : 'No matching shops',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.shops.isEmpty
                          ? widget.isOwner
                                ? 'Add your first shop or import your Excel list.'
                                : 'An owner will share your assigned shops.'
                          : 'Try another name, letter group, area or location filter.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DirectoryDesign.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.shops.isEmpty && widget.isOwner)
                      FilledButton.icon(
                        onPressed: widget.busy ? null : widget.onAdd,
                        icon: const Icon(Icons.add),
                        label: const Text('Add first shop'),
                      )
                    else if (widget.shops.isNotEmpty)
                      TextButton(
                        onPressed: _reset,
                        child: const Text('Reset filters'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
