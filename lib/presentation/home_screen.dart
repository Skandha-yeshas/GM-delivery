import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';
import '../domain/maps_location.dart';
import 'common.dart';
import 'shop_form.dart';
import 'shop_directory.dart';
import 'dispatch_design.dart';
import 'owner_route_planner.dart';
import 'shop_import_screen.dart';
import 'bill_scan_screen.dart';
import 'driver_delivery_board.dart';
import 'driver_shop_search.dart';
import 'collection_form.dart';
import 'ledger_screen.dart';
import 'settlement_screen.dart';
import '../domain/ledger.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, this.onSignOut});
  final DeliveryController controller;
  final Future<void> Function()? onSignOut;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  bool _routeDirty = false;
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
    _tab = c.isOwner ? 0 : 1;
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
    builder: (context, _) => Theme(
      data: DirectoryDesign.theme(Theme.of(context)),
      child: Scaffold(
        appBar: _directoryAppBar(),
        body: Column(
          children: [
            _connectionBanner(),
            Expanded(child: _tab == 0 ? _shopList() : _deliveryList()),
          ],
        ),
        floatingActionButton: c.isOwner && _tab == 0
            ? FloatingActionButton.extended(
                key: ValueKey('home-add-$_tab'),
                onPressed: c.busy
                    ? null
                    : () {
                        if (_tab == 0) {
                          _edit();
                        } else {
                          _scanBill();
                        }
                      },
                icon: Icon(_tab == 0 ? Icons.add : Icons.photo_camera_outlined),
                label: Text(_tab == 0 ? 'Add shop' : 'Scan Next Bill'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (tab) {
            if (_routeDirty && tab != _tab) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Save the delivery order or reset the draft before switching tabs.',
                  ),
                ),
              );
              return;
            }
            setState(() => _tab = tab);
          },
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: c.isOwner ? 'All Shops' : 'Shops',
            ),
            NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route_rounded),
              label: c.isOwner ? 'Assign Delivery' : 'Deliveries',
            ),
          ],
        ),
      ),
    ),
  );

  AppBar _directoryAppBar() => AppBar(
    toolbarHeight: 80,
    titleSpacing: 16,
    title: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DirectoryDesign.navy,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'GM',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'G.M. Delivery',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: DirectoryDesign.navy,
                ),
              ),
              Text(
                c.isOwner
                    ? 'Wholesale Stationery Logistics'
                    : (c.profile?.name ?? 'Delivery account'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: DirectoryDesign.muted),
              ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      if (!c.isOwner)
        IconButton(
          tooltip: 'Daily settlements',
          icon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SettlementsScreen(controller: c)),
          ),
        ),
      IconButton(
        tooltip: 'Account and saved records',
        onPressed: _accountSheet,
        icon: CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xffdce1ff),
          child: Text(
            (c.profile?.name.trim().isNotEmpty ?? false)
                ? c.profile!.name.trim().characters.first.toUpperCase()
                : c.isOwner
                ? 'O'
                : 'D',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DirectoryDesign.navy,
            ),
          ),
        ),
      ),
      if (widget.onSignOut != null)
        IconButton(
          tooltip: 'Sign out',
          onPressed: c.busy
              ? null
              : () => runAction(context, widget.onSignOut!),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xffffece9),
            foregroundColor: const Color(0xffba1a1a),
          ),
          icon: const Icon(Icons.logout, size: 20),
        ),
      const SizedBox(width: 8),
    ],
    bottom: c.busy
        ? const PreferredSize(
            preferredSize: Size.fromHeight(2),
            child: LinearProgressIndicator(minHeight: 2),
          )
        : null,
  );

  Widget _connectionBanner() {
    final failure = c.syncError ?? c.ledgerSyncError ?? c.settlementSyncError;
    final message = !c.shared
        ? 'Saved on this phone only. Sharing is not enabled yet.'
        : failure ??
              (c.pendingCount > 0
                  ? '${c.pendingCount} operation(s) waiting to sync'
                  : c.lastSynced == null
                  ? 'Downloading shared records…'
                  : 'Shared records • ${c.profile?.name ?? ''}');
    return Container(
      width: double.infinity,
      color: failure == null
          ? const Color(0xffe5eee6)
          : const Color(0xffffedda),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            !c.shared
                ? Icons.phone_android_rounded
                : failure != null
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
    if (!c.isOwner) {
      final assigned = c.stops
          .where((s) => s.driverId == c.accountId)
          .map((s) => s.shopId)
          .toSet();
      return DriverShopSearch(
        shops: c.shops.where((s) => assigned.contains(s.id)).toList(),
        todayShopIds: c.stopsFor(DateTime.now()).map((s) => s.shopId).toSet(),
        searchController: _shopSearch,
        search: _search,
        onSearch: (value) => setState(() => _search = value),
        busy: c.busy,
        onRefresh: c.refresh,
        onOpen: _details,
        onCall: (shop) => callShop(context, shop),
        onMap: (shop) => showDriverShopLocation(
          context,
          shop,
          onNavigate: (shop) => navigateTo(context, shop),
          onCall: (shop) => callShop(context, shop),
        ),
      );
    }
    return ShopDirectory(
      shops: c.shops,
      search: _search,
      searchController: _shopSearch,
      onSearch: (value) => setState(() => _search = value),
      area: _area,
      onArea: (value) => setState(() => _area = value),
      locationFilter: _locationFilter,
      onLocationFilter: (value) => setState(() => _locationFilter = value),
      isOwner: c.isOwner,
      busy: c.busy,
      onImport: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ShopImportScreen(controller: c)),
      ),
      onAdd: () => _edit(),
      onOpen: _details,
      onCall: (shop) => callShop(context, shop),
      onRefresh: c.refresh,
    );
  }

  Widget _deliveryList() {
    if (c.isOwner) {
      return OwnerRoutePlanner(
        controller: c,
        date: _date,
        onScan: _scanBill,
        onAddStops: () => showAddStops(context, c, _date),
        onChooseDate: _chooseDate,
        stopBuilder: _stopCard,
        onDraftChanged: (dirty) => setState(() => _routeDirty = dirty),
      );
    }
    return DriverDeliveryBoard(
      controller: c,
      date: _date,
      onChooseDate: _chooseDate,
      onNavigate: (shop) => navigateTo(context, shop),
      onCall: (shop) => callShop(context, shop),
      onShop: _details,
      onDelivered: _openCollection,
      onFailed: (stop) => _result(stop, initialStatus: VisitStatus.failed),
      onReopen: _reset,
      onLedger: (shop) => openShopLedger(context, c, shop.id),
      onCollection: _openCollection,
      onSettlement: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettlementScreen(
            controller: c,
            driverId: c.accountId,
            date: dateKey(_date),
          ),
        ),
      ),
    );
  }

  Future<void> _openCollection(DeliveryStop stop) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          CollectionForm(controller: c, shopId: stop.shopId, stopId: stop.id),
    ),
  );

  Widget _stopCard(DeliveryStop stop, int number) {
    final shop = c.shopFor(stop.shopId);
    return shop == null
        ? const SizedBox.shrink()
        : _dispatchStopCard(stop, shop, number);
  }

  Future<void> _scanBill() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BillScanScreen(controller: c, date: _date),
    ),
  );

  Widget _dispatchStopCard(DeliveryStop stop, Shop shop, int number) {
    final queued = c.pendingStopIds.contains(stop.id);
    final driver = c.profiles
        .where((profile) => profile.id == stop.driverId)
        .firstOrNull;
    final color = stop.status == VisitStatus.failed
        ? const Color(0xffa66b12)
        : DirectoryDesign.teal;
    return DispatchCard(
      key: ValueKey('dispatch-stop-${stop.id}'),
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              DispatchBadge(
                queued
                    ? 'Waiting to sync'
                    : stop.status == VisitStatus.pending
                    ? 'Scheduled for dispatch'
                    : stop.status.label,
                icon: queued
                    ? Icons.cloud_upload_outlined
                    : stop.status == VisitStatus.pending
                    ? Icons.schedule_send_outlined
                    : Icons.task_alt,
                color: queued ? const Color(0xffa66b12) : color,
              ),
              DispatchBadge(
                'Stop $number',
                icon: Icons.route_outlined,
                color: DirectoryDesign.navy,
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _details(shop),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                shop.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DispatchDropPoint(shop: shop, onCall: () => callShop(context, shop)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.person_pin_circle_outlined,
                size: 19,
                color: DirectoryDesign.teal,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Assigned to ${driver?.name ?? 'delivery account unavailable'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Outstanding: ${rupees(c.balanceFor(shop.id).balancePaise)}',
            style: const TextStyle(fontSize: 13, color: DirectoryDesign.muted),
          ),
          if (stop.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(stop.reason),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: shop.readyForDelivery
                    ? () => navigateTo(context, shop)
                    : null,
                icon: const Icon(Icons.near_me_outlined, size: 17),
                label: const Text('View drop point'),
              ),
              if (stop.status == VisitStatus.pending)
                FilledButton.icon(
                  onPressed: queued || c.busy ? null : () => _result(stop),
                  icon: const Icon(Icons.task_alt, size: 17),
                  label: const Text('Update result'),
                ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Delivery actions',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: () => openShopLedger(context, c, shop.id),
                    icon: const Icon(Icons.receipt_long_outlined, size: 17),
                    label: const Text('Ledger'),
                  ),
                  if (stop.status == VisitStatus.delivered)
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CollectionForm(
                            controller: c,
                            shopId: shop.id,
                            stopId: stop.id,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.payments_outlined, size: 17),
                      label: const Text('Record collection'),
                    ),
                  if (stop.status != VisitStatus.pending && !queued)
                    TextButton(
                      onPressed: c.busy ? null : () => _reset(stop),
                      child: const Text('Reopen delivery'),
                    ),
                  if (stop.status == VisitStatus.pending && !queued)
                    TextButton.icon(
                      onPressed: c.busy ? null : () => _removeStop(stop),
                      icon: const Icon(Icons.remove_circle_outline, size: 17),
                      label: const Text('Remove this stop'),
                    ),
                ],
              ),
            ],
          ),
        ],
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

  Future<void> _result(
    DeliveryStop stop, {
    VisitStatus initialStatus = VisitStatus.delivered,
  }) async {
    final reason = TextEditingController();
    var status = initialStatus;
    final form = GlobalKey<FormState>();
    final result = await showDialog<VisitStatus>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delivery result'),
          scrollable: true,
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
      if (result == VisitStatus.delivered) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollectionForm(
              controller: c,
              shopId: stop.shopId,
              stopId: stop.id,
            ),
          ),
        );
        return;
      }
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
      child: SingleChildScrollView(
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettlementsScreen(controller: c),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Daily settlements'),
                ),
                if (c.isOwner)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OutstandingScreen(controller: c),
                        ),
                      );
                    },
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Outstanding balances'),
                  ),
                if (c.shared)
                  TextButton.icon(
                    onPressed: c.busy
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            runAction(context, c.refresh);
                          },
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync records'),
                  ),
              ],
            ),
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
            if (c.pendingLedger.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${c.pendingLedger.length} financial operation(s) saved on this phone.',
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectionQueueScreen(controller: c),
                    ),
                  );
                },
                child: const Text('View collection sync queue'),
              ),
            ],
            if (c.pendingSettlements.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${c.pendingSettlements.length} settlement request(s) saved on this phone.',
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettlementsScreen(controller: c),
                    ),
                  );
                },
                child: const Text('Review settlement sync requests'),
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
    final existing = widget.controller
        .stopsFor(widget.date)
        .map((s) => s.shopId)
        .toSet();
    if (dateKey(widget.date).compareTo(dateKey(DateTime.now())) >= 0) {
      _selected.addAll(
        widget.controller.shops
            .where(
              (s) =>
                  s.readyForDelivery &&
                  !existing.contains(s.id) &&
                  widget.controller.balanceFor(s.id).collectNextVisit,
            )
            .map((s) => s.id),
      );
    }
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
                              subtitle: Text(
                                '${shop.area}${c.balanceFor(shop.id).collectNextVisit ? ' · Collect outstanding balance' : ''}',
                              ),
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
            if (shop.contactName.isNotEmpty)
              _detail(
                Icons.person_outline,
                'Proprietor / contact person',
                shop.contactName,
              ),
            if (shop.postalCode.isNotEmpty)
              _detail(
                Icons.local_post_office_outlined,
                'PIN code',
                shop.postalCode,
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
            OutlinedButton.icon(
              onPressed: () => openShopLedger(context, controller, shop.id),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View shop ledger'),
            ),
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
