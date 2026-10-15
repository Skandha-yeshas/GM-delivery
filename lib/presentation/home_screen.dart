import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';
import '../domain/maps_location.dart';
import 'common.dart';
import 'shop_form.dart';
import 'shop_import_screen.dart';
import 'bill_scan_screen.dart';
import 'owner_dashboard.dart';
import 'workspace_design.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, this.onSignOut});
  final DeliveryController controller;
  final Future<void> Function()? onSignOut;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  String _search = '';
  final _shopSearch = TextEditingController();
  String? _area;
  String _locationFilter = 'All locations';
  DateTime _date = DateTime.now();
  Timer? _syncTimer;
  DeliveryController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _tab = c.isOwner ? 2 : 1;
    WidgetsBinding.instance.addObserver(this);
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          c.shared &&
          !c.busy) {
        unawaited(c.refresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && c.shared && !c.busy) {
      unawaited(c.refresh());
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _shopSearch.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _edit({Shop? shop}) async => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ShopForm(controller: c, shop: shop),
    ),
  );

  void _details(Shop shop) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ShopDetails(controller: c, shopId: shop.id),
    ),
  );

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (result != null && mounted) setState(() => _date = result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WorkspaceColors.ink,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Text(
                'GM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'G.M. Enterprises',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -.5,
                    ),
                  ),
                  Text(
                    c.isOwner ? 'OWNER WORKSPACE' : 'DELIVERY WORKSPACE',
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.4,
                      color: WorkspaceColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (c.shared)
            IconButton(
              tooltip: 'Sync records',
              onPressed: c.busy ? null : () => runAction(context, c.refresh),
              icon: const Icon(Icons.sync_rounded),
            ),
          IconButton(
            tooltip: 'Account and saved records',
            onPressed: _accountSheet,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
        bottom: c.busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          _connectionBanner(),
          Expanded(
            child: _tab == 2 && c.isOwner
                ? OwnerDashboard(
                    controller: c,
                    onScan: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BillScanScreen(controller: c, date: DateTime.now()),
                      ),
                    ),
                    onShops: () => setState(() {
                      _tab = 0;
                      _search = '';
                      _shopSearch.clear();
                      _area = null;
                      _locationFilter = 'All locations';
                    }),
                    onReadyLocations: () => setState(() {
                      _tab = 0;
                      _search = '';
                      _shopSearch.clear();
                      _area = null;
                      _locationFilter = 'Ready for delivery';
                    }),
                    onDeliveries: () => setState(() {
                      _tab = 1;
                      _date = DateTime.now();
                    }),
                    onAddShop: () => _edit(),
                    onImport: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShopImportScreen(controller: c),
                      ),
                    ),
                    onMissingLocations: () => setState(() {
                      _tab = 0;
                      _search = '';
                      _shopSearch.clear();
                      _area = null;
                      _locationFilter = 'Needs attention';
                    }),
                  )
                : _tab == 0
                ? _shopList()
                : _deliveryList(),
          ),
        ],
      ),
      floatingActionButton: c.isOwner && _tab != 2
          ? FloatingActionButton.extended(
              onPressed: c.busy
                  ? null
                  : () {
                      if (_tab == 0) {
                        _edit();
                      } else {
                        showAddStops(context, c, _date);
                      }
                    },
              icon: Icon(
                _tab == 0
                    ? Icons.add_location_alt_outlined
                    : Icons.playlist_add_rounded,
              ),
              label: Text(_tab == 0 ? 'Add shop' : 'Add stops'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: c.isOwner
            ? (_tab == 2 ? 0 : _tab + 1)
            : (_tab == 2 ? 1 : _tab),
        onDestinationSelected: (tab) =>
            setState(() => _tab = c.isOwner ? (tab == 0 ? 2 : tab - 1) : tab),
        destinations: [
          if (c.isOwner)
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Overview',
            ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'Shops',
          ),
          const NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route_rounded),
            label: 'Deliveries',
          ),
        ],
      ),
    ),
  );

  Widget _connectionBanner() {
    final message = !c.shared
        ? 'Saved on this phone only. Sharing is not enabled yet.'
        : c.syncError != null
        ? c.syncError!
        : c.pending.isNotEmpty
        ? '${c.pending.length} result(s) waiting to sync'
        : c.lastSynced == null
        ? 'Downloading shared records…'
        : 'Shared records • ${c.profile?.name ?? ''}';
    return Container(
      width: double.infinity,
      color: c.syncError == null
          ? const Color(0xffe5eee6)
          : const Color(0xffffedda),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            !c.shared
                ? Icons.phone_android_rounded
                : c.syncError != null
                ? Icons.cloud_off_outlined
                : Icons.cloud_done_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _shopList() {
    final areas = c.shops.map((s) => s.area).toSet().toList()..sort();
    final matching = c.shops
        .where(
          (s) =>
              (_area == null || s.area == _area) &&
              (_locationFilter == 'All locations' ||
                  (_locationFilter == 'Needs attention' &&
                      !s.readyForDelivery) ||
                  s.locationStatus == _locationFilter) &&
              '${s.name} ${s.area} ${s.address} ${s.landmark} ${s.phone}'
                  .toLowerCase()
                  .contains(_search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Shop directory',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${c.shops.length} saved',
                style: const TextStyle(color: Color(0xff527064)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _shopSearch,
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              hintText: 'Search shop, area or landmark',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        if (c.isOwner)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _locationFilter,
                    items:
                        [
                              'All locations',
                              'Needs attention',
                              'Needs location',
                              'Needs verification',
                              'Ready for delivery',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setState(() => _locationFilter = value!),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: c.busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShopImportScreen(controller: c),
                          ),
                        ),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import Excel'),
                ),
              ],
            ),
          ),
        if (areas.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All areas'),
                    selected: _area == null,
                    onSelected: (_) => setState(() => _area = null),
                  ),
                ),
                for (final area in areas)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(area),
                      selected: _area == area,
                      onSelected: (_) =>
                          setState(() => _area = _area == area ? null : area),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: matching.isEmpty
              ? EmptyState(
                  icon: Icons.add_business_outlined,
                  title: c.shops.isEmpty
                      ? 'Your shop directory starts here'
                      : 'No matching shops',
                  message: c.shops.isEmpty
                      ? c.isOwner
                            ? 'Add your first shop, capture its entrance location, and save a landmark.'
                            : 'An owner will assign shops for your deliveries. Sync after the list is ready.'
                      : 'Try another shop name or area.',
                  action: c.shops.isEmpty && c.isOwner
                      ? FilledButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add first shop'),
                        )
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: c.refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: matching.length,
                    itemBuilder: (context, index) {
                      final shop = matching[index];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xffe5eee6),
                            child: Icon(
                              shop.readyForDelivery
                                  ? Icons.location_on_outlined
                                  : Icons.location_off_outlined,
                              color: shop.readyForDelivery
                                  ? const Color(0xff09685d)
                                  : Colors.deepOrange,
                            ),
                          ),
                          title: Text(
                            shop.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${shop.area}\n${shop.readyForDelivery
                                ? shop.landmark.isEmpty
                                      ? shop.locationDescription
                                      : shop.landmark
                                : shop.locationStatus}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _details(shop),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _deliveryList() {
    final stops = c.stopsFor(_date);
    final complete = stops
        .where((s) => s.status == VisitStatus.delivered)
        .length;
    final pending = stops.where((s) => s.status == VisitStatus.pending).length;
    final next = stops
        .where((s) => s.status == VisitStatus.pending)
        .firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dateKey(_date) == dateKey(DateTime.now())
                      ? 'Today’s deliveries'
                      : 'Delivery list',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(readableDate(_date)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _stat('Stops', stops.length),
              const SizedBox(width: 10),
              _stat('Pending', pending),
              const SizedBox(width: 10),
              _stat('Delivered', complete),
            ],
          ),
        ),
        if (next != null && c.shopFor(next.shopId) != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => navigateTo(context, c.shopFor(next.shopId)!),
                icon: const Icon(Icons.navigation_outlined),
                label: Text(
                  'Navigate to ${c.shopFor(next.shopId)!.name}',
                  maxLines: 2,
                ),
              ),
            ),
          ),
        if (c.isOwner)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: c.busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BillScanScreen(controller: c, date: _date),
                        ),
                      ),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan bill to add delivery'),
              ),
            ),
          ),
        Expanded(
          child: stops.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: EmptyState(
                    icon: Icons.route_rounded,
                    title: 'No stops for this day',
                    message: c.isOwner
                        ? 'Choose shops and assign a delivery person.'
                        : 'Sync to check for your assigned deliveries.',
                    action: c.isOwner
                        ? FilledButton.icon(
                            onPressed: () => showAddStops(context, c, _date),
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Prepare delivery list'),
                          )
                        : null,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: c.refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
                    itemCount: stops.length,
                    itemBuilder: (context, index) =>
                        _stopCard(stops[index], index + 1),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _stat(String label, int value) => Expanded(
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xff527064)),
          ),
        ],
      ),
    ),
  );

  Widget _stopCard(DeliveryStop stop, int number) {
    final shop = c.shopFor(stop.shopId);
    if (shop == null) return const SizedBox.shrink();
    final queued = c.pendingStopIds.contains(stop.id);
    final done = stop.status == VisitStatus.delivered;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: done
                      ? const Color(0xffe5eee6)
                      : const Color(0xffedf1f5),
                  child: done
                      ? const Icon(Icons.check, size: 18)
                      : Text('$number'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _details(shop),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          shop.area,
                          style: const TextStyle(color: Color(0xff527064)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (c.isOwner && stop.status == VisitStatus.pending && !queued)
                  IconButton(
                    tooltip: 'Remove this stop',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: c.busy ? null : () => _removeStop(stop),
                  ),
              ],
            ),
            if (shop.landmark.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(shop.landmark),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${stop.status.label}${queued ? ' • waiting to sync' : ''}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: stop.status == VisitStatus.failed
                      ? Colors.deepOrange
                      : const Color(0xff09685d),
                ),
              ),
            ),
            if (stop.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(stop.reason),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: shop.readyForDelivery
                      ? () => navigateTo(context, shop)
                      : null,
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: const Text('Navigate'),
                ),
                if (shop.phone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => callShop(context, shop),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Call'),
                  ),
                if (stop.status == VisitStatus.pending)
                  OutlinedButton.icon(
                    onPressed: c.busy || queued ? null : () => _result(stop),
                    icon: const Icon(Icons.task_alt, size: 18),
                    label: const Text('Update result'),
                  ),
                if (stop.status != VisitStatus.pending && !queued)
                  TextButton(
                    onPressed: c.busy ? null : () => _reset(stop),
                    child: const Text('Reopen delivery'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeStop(DeliveryStop stop) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this delivery?'),
        content: const Text(
          'The shop stays in the directory. Only this day’s pending stop is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await runAction(context, () => c.removeStop(stop));
    }
  }

  Future<void> _reset(DeliveryStop stop) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen this delivery?'),
        content: const Text('Its status will return to pending.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await runAction(context, () => c.recordVisit(stop, VisitStatus.pending));
    }
  }

  Future<void> _result(DeliveryStop stop) async {
    final reason = TextEditingController();
    var status = VisitStatus.delivered;
    final form = GlobalKey<FormState>();
    final result = await showDialog<VisitStatus>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delivery result'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<VisitStatus>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Result'),
                  items: [VisitStatus.delivered, VisitStatus.failed]
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (s) => setDialogState(() => status = s!),
                ),
                if (status == VisitStatus.failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextFormField(
                      controller: reason,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        hintText: 'For example, shop closed',
                      ),
                      validator: (s) => s == null || s.trim().isEmpty
                          ? 'Enter a reason.'
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, status);
                }
              },
              child: const Text('Save result'),
            ),
          ],
        ),
      ),
    );
    final note = reason.text;
    // Dialog route animations may still reference the controller until disposed.
    if (result != null && mounted) {
      await runAction(
        context,
        () => c.recordVisit(stop, result, reason: note),
        success: c.shared
            ? 'Result saved. Check the sync indicator.'
            : 'Result saved on this phone.',
      );
    }
  }

  void _accountSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.profile?.name ?? 'G.M. Enterprises',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(c.isOwner ? 'Owner account' : 'Delivery account'),
            const SizedBox(height: 16),
            Text(
              c.shared
                  ? 'Records are shared between your company’s signed-in phones.'
                  : 'You can try the location workflow on this phone. Other phones will not see these records until sharing is set up. Local trial records stay separate from shared records.',
            ),
            if (c.lastSynced != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Last sync: ${readableDate(c.lastSynced!)} '
                  '${c.lastSynced!.hour.toString().padLeft(2, '0')}:${c.lastSynced!.minute.toString().padLeft(2, '0')}',
                ),
              ),
            if (c.pending.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('${c.pending.length} delivery result(s) waiting to sync.'),
              TextButton(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Discard unsynced results?'),
                      content: const Text(
                        'Use this only after an owner has reviewed a conflict. The queued results will be replaced with the shared records.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Keep results'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Discard and reload'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true && mounted) {
                    await runAction(context, c.discardPending);
                  }
                },
                child: const Text('Resolve a sync conflict'),
              ),
            ],
            if (widget.onSignOut != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  onPressed: c.busy
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          runAction(context, widget.onSignOut!);
                        },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showAddStops(
  BuildContext context,
  DeliveryController controller,
  DateTime date,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => AddStopsSheet(controller: controller, date: date),
);

class AddStopsSheet extends StatefulWidget {
  const AddStopsSheet({
    super.key,
    required this.controller,
    required this.date,
  });
  final DeliveryController controller;
  final DateTime date;
  @override
  State<AddStopsSheet> createState() => _AddStopsSheetState();
}

class _AddStopsSheetState extends State<AddStopsSheet> {
  final Set<String> _selected = {};
  String _search = '';
  String? _driver;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _driver = widget.controller.drivers.firstOrNull?.id;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final id in _selected.toList()) {
        final shop = widget.controller.shopFor(id);
        if (shop != null) {
          await widget.controller.addStop(shop, widget.date, _driver!);
        }
        _selected.remove(id);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final existing = c.stopsFor(widget.date).map((s) => s.shopId).toSet();
    final eligible =
        c.shops
            .where(
              (s) =>
                  s.readyForDelivery &&
                  !existing.contains(s.id) &&
                  '${s.name} ${s.area}'.toLowerCase().contains(
                    _search.toLowerCase(),
                  ),
            )
            .toList()
          ..sort(
            (a, b) => '${a.area} ${a.name}'.compareTo('${b.area} ${b.name}'),
          );
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prepare ${readableDate(widget.date)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _driver,
                  decoration: const InputDecoration(
                    labelText: 'Delivery person',
                  ),
                  items: c.drivers
                      .map(
                        (d) =>
                            DropdownMenuItem(value: d.id, child: Text(d.name)),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _driver = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search shop or area',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: c.drivers.isEmpty
                      ? const EmptyState(
                          icon: Icons.person_add_alt,
                          title: 'No delivery account yet',
                          message:
                              'Set up the delivery person’s account before assigning stops.',
                        )
                      : eligible.isEmpty
                      ? const EmptyState(
                          icon: Icons.location_off_outlined,
                          title: 'No available shops',
                          message:
                              'Verify shop locations first. Shops already on this list are excluded.',
                        )
                      : ListView.builder(
                          itemCount: eligible.length,
                          itemBuilder: (context, index) {
                            final shop = eligible[index];
                            return CheckboxListTile(
                              value: _selected.contains(shop.id),
                              title: Text(shop.name),
                              subtitle: Text(shop.area),
                              onChanged: _saving
                                  ? null
                                  : (checked) => setState(() {
                                      if (checked == true) {
                                        _selected.add(shop.id);
                                      } else {
                                        _selected.remove(shop.id);
                                      }
                                    }),
                            );
                          },
                        ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving || _selected.isEmpty || _driver == null
                        ? null
                        : _save,
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(
                      _saving
                          ? 'Adding stops…'
                          : 'Add ${_selected.length} selected stops',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShopDetails extends StatelessWidget {
  const ShopDetails({
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
      final shop = controller.shopFor(shopId);
      if (shop == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Shop unavailable')),
          body: const EmptyState(
            icon: Icons.storefront_outlined,
            title: 'Shop unavailable',
            message: 'This shop may no longer be assigned to your account.',
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(shop.name),
          actions: [
            if (controller.isOwner)
              IconButton(
                tooltip: 'Edit shop',
                icon: const Icon(Icons.edit_outlined),
                onPressed: controller.busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ShopForm(controller: controller, shop: shop),
                        ),
                      ),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ShopPhoto(shop: shop, height: 220),
            const SizedBox(height: 22),
            Text(
              shop.name,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              shop.area,
              style: const TextStyle(fontSize: 17, color: Color(0xff527064)),
            ),
            const SizedBox(height: 20),
            _detail(
              Icons.location_on_outlined,
              'Delivery location',
              shop.locationDescription,
            ),
            if (shop.address.isNotEmpty)
              _detail(Icons.home_work_outlined, 'Address', shop.address),
            if (shop.landmark.isNotEmpty)
              _detail(Icons.near_me_outlined, 'Landmark', shop.landmark),
            if (shop.notes.isNotEmpty)
              _detail(Icons.info_outline, 'Delivery instructions', shop.notes),
            if (shop.phone.isNotEmpty)
              _detail(Icons.phone_outlined, 'Contact', shop.phone),
            if (shop.hasCoordinates)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  '${shop.latitude!.toStringAsFixed(6)}, ${shop.longitude!.toStringAsFixed(6)}',
                  style: const TextStyle(color: Color(0xff527064)),
                ),
              ),
            const SizedBox(height: 12),
            if (controller.isOwner) ...[
              if (!shop.hasLocation)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Paste a shop or dropped-pin Google Maps link, or capture its entrance location during a visit. Address and landmark details can also be saved for later.',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => runAction(context, () async {
                  final uri = shop.mapsUrl.isEmpty
                      ? shopSearchUri(shop.name, shop.address, shop.area)
                      : googleMapsUri(shop.mapsUrl);
                  if (!await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('Could not open Google Maps.');
                  }
                }),
                icon: const Icon(Icons.map_outlined),
                label: Text(
                  shop.mapsUrl.isEmpty
                      ? 'Search shop in Google Maps'
                      : 'Open saved Maps link',
                ),
              ),
            ],
            FilledButton.icon(
              onPressed: shop.readyForDelivery
                  ? () => navigateTo(context, shop)
                  : null,
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Navigate to shop'),
            ),
            if (shop.phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: () => callShop(context, shop),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call shop'),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _detail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: const Color(0xff09685d)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xff527064)),
              ),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    ),
  );
}
