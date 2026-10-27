import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../application/delivery_controller.dart';
import '../data/bill_scan_service.dart';
import '../data/shop_location_service.dart';
import '../domain/bill_shop_matcher.dart';
import '../domain/models.dart';
import 'common.dart';
import 'shop_form.dart';
import 'dispatch_design.dart';
import 'shop_directory.dart';

class BillScanScreen extends StatefulWidget {
  const BillScanScreen({
    super.key,
    required this.controller,
    required this.date,
    this.scanner,
    this.locationService,
  });
  final DeliveryController controller;
  final DateTime date;
  final BillScanService? scanner;
  final ShopLocationService? locationService;
  @override
  State<BillScanScreen> createState() => _BillScanScreenState();
}

class _BillScanScreenState extends State<BillScanScreen> {
  final _name = TextEditingController();
  List<String> _detectedNames = [];
  late final BillScanService _scanner;
  String? _selectedId, _driver, _message;
  Uint8List? _photoBytes;
  bool _busy = true, _added = false;
  bool _matching = false;
  int _matchGeneration = 0;
  int _photoRevision = 0;
  Timer? _matchTimer;
  List<BillShopMatch> _matches = [];
  DeliveryController get c => widget.controller;
  File get _draft => File(p.join(c.photoDirectory.path, 'bill_scan_draft.jpg'));

  @override
  void initState() {
    super.initState();
    _scanner = widget.scanner ?? DeviceBillScanService();
    _driver = c.drivers.firstOrNull?.id;
    unawaited(_recover());
  }

  @override
  void dispose() {
    _matchGeneration++;
    _matchTimer?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    try {
      if (!c.isOwner) return;
      final state = await c.store.getSetting('bill_scan_state');
      if (!mounted) return;
      if (state == 'picking') {
        final recovered = await _scanner.recoverLostImage();
        if (recovered != null && mounted) {
          await _readPhoto(recovered);
        } else if (mounted && await _draft.exists()) {
          await _readPhoto(_draft.path);
        } else {
          await c.store.setting('bill_scan_state', '');
        }
      } else if (state == 'ready' && await _draft.exists() && mounted) {
        await _readPhoto(_draft.path);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _message = 'Could not resume the last photo. ${errorText(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readPhoto(String path) async {
    if (!mounted) return;
    _matchTimer?.cancel();
    _matchGeneration++;
    if (path != _draft.path) await File(path).copy(_draft.path);
    if (!mounted) return;
    await c.store.setting('bill_scan_state', 'ready');
    final bytes = await _draft.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBytes = bytes;
      _photoRevision++;
      _selectedId = null;
      _added = false;
      _name.clear();
      _matches = [];
    });
    final text = await _scanner.readText(_draft.path);
    if (!mounted) return;
    setState(() {
      _detectedNames = extractShopNames(text);
      _name.text = _detectedNames.firstOrNull ?? '';
      _message = _name.text.isEmpty
          ? 'No shop name found. Capture the name more closely, or type it below.'
          : 'Check the detected shop name below.';
    });
    await _suggest(_name.text);
  }

  Future<void> _suggest(String text) async {
    final generation = ++_matchGeneration;
    if (!mounted) return;
    setState(() {
      _matching = true;
      _matches = [];
    });
    try {
      final result = await compute(matchBillShopRequest, (
        text.trim().isEmpty ? '' : 'Customer: $text',
        List<Shop>.of(c.shops),
      ));
      if (mounted && generation == _matchGeneration) {
        final exact = result
            .where(
              (m) => normalizeShopName(m.shop.name) == normalizeShopName(text),
            )
            .toList();
        setState(() {
          _matches = result.take(5).toList();
          _selectedId = exact.length == 1 ? exact.single.shop.id : null;
        });
      }
    } catch (_) {
      if (mounted && generation == _matchGeneration) {
        setState(
          () => _message =
              'Could not suggest a match. Search the saved shop name manually.',
        );
      }
    } finally {
      if (mounted && generation == _matchGeneration) {
        setState(() => _matching = false);
      }
    }
  }

  void _nameChanged(String value) {
    _matchTimer?.cancel();
    _matchGeneration++;
    setState(() {
      _selectedId = null;
      _added = false;
      _matching = true;
      _matches = [];
    });
    _matchTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_suggest(value)),
    );
  }

  Future<void> _pick(ImageSource source) async {
    _matchTimer?.cancel();
    _matchGeneration++;
    setState(() {
      _busy = true;
      _matching = false;
      _message = null;
    });
    try {
      await c.store.setting('bill_scan_state', 'picking');
      final path = await _scanner.pick(source);
      if (!mounted) return;
      if (path != null) {
        await _readPhoto(path);
      } else {
        await c.store.setting(
          'bill_scan_state',
          await _draft.exists() ? 'ready' : '',
        );
        if (mounted && _name.text.isNotEmpty) await _suggest(_name.text);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              'Could not read the bill photo. Try again or search manually. ${errorText(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createShop({bool captureLocation = false}) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    String? savedId;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShopForm(
          controller: c,
          initialName: name,
          locationService: widget.locationService,
          captureLocationOnOpen: captureLocation,
          onSaved: (id) => savedId = id,
        ),
      ),
    );
    if (!mounted || savedId == null) return;
    final shop = c.shopFor(savedId!);
    if (shop == null) return;
    _name.text = shop.name;
    await _suggest(shop.name);
    if (mounted) {
      setState(() {
        _selectedId = shop.id;
        _message = shop.readyForDelivery
            ? 'Shop added. Its location is ready for delivery.'
            : 'Shop added. Save a Maps link or its entrance location to add this delivery.';
      });
    }
  }

  Future<void> _add() async {
    final shop = _selectedId == null ? null : c.shopFor(_selectedId!);
    if (shop == null || _driver == null) return;
    setState(() => _busy = true);
    try {
      await c.addStop(shop, widget.date, _driver!);
      if (!mounted) return;
      // Clear the resumable draft only after the delivery was saved.
      setState(() {
        _added = true;
        _photoBytes = null;
        _matches = [];
        _name.clear();
        _message = '${shop.name} added. Scan the next bill to continue.';
      });
      try {
        await c.store.setting('bill_scan_state', '');
        if (await _draft.exists()) await _draft.delete();
      } catch (_) {
        // Saving the delivery succeeded even if temporary-photo cleanup fails.
      }
    } catch (error) {
      if (mounted) setState(() => _message = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(Shop shop) => runAction(context, () async {
    final uri = locationPreviewUri(shop);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open the map.');
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.isOwner) {
        return Scaffold(
          appBar: AppBar(title: const Text('Scan shop name')),
          body: const Center(
            child: Text('Only owners can prepare deliveries.'),
          ),
        );
      }
      final selected = _selectedId == null ? null : c.shopFor(_selectedId!);
      final options = _matches
          .map((m) => c.shopFor(m.shop.id))
          .whereType<Shop>()
          .toList();
      final exactMatches = options
          .where(
            (s) => normalizeShopName(s.name) == normalizeShopName(_name.text),
          )
          .length;
      final existing = c
          .stopsFor(widget.date)
          .any((s) => s.shopId == _selectedId);
      final enabled = !_busy && !_matching && !c.busy;
      final canAdd =
          enabled &&
          !_added &&
          !existing &&
          selected?.readyForDelivery == true &&
          c.drivers.any((d) => d.id == _driver);
      return Theme(
        data: DirectoryDesign.theme(Theme.of(context)),
        child: PopScope(
          canPop: !_busy,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(
                'Assign Delivery',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: enabled ? () => _pick(ImageSource.camera) : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Scan Next Bill'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                BillUploadPanel(
                  onCamera: enabled ? () => _pick(ImageSource.camera) : null,
                  onGallery: enabled ? () => _pick(ImageSource.gallery) : null,
                  showGallery: true,
                  busy: _busy,
                  hasPhoto: _photoBytes != null,
                  shopName: _name.text,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    DispatchBadge(
                      readableDate(widget.date),
                      icon: Icons.calendar_today_outlined,
                      color: DirectoryDesign.navy,
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: Text(
                        'View delivery list (${c.stopsFor(widget.date).length})',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DispatchCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Review shop name',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Shop name',
                          hintText: 'Scan or type the name',
                          counterText: '',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                        onChanged: _nameChanged,
                      ),
                      if (_detectedNames.length > 1) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Choose the customer name',
                          style: TextStyle(fontSize: 12),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final name in _detectedNames)
                              ActionChip(
                                label: Text(name),
                                onPressed: enabled
                                    ? () {
                                        _name.text = name;
                                        _nameChanged(name);
                                      }
                                    : null,
                              ),
                          ],
                        ),
                      ],
                      if (_matching || _busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (_matching)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Finding matching shops…',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: _added
                                  ? DirectoryDesign.teal
                                  : DirectoryDesign.muted,
                            ),
                          ),
                        ),
                      if (_photoBytes != null && !_added)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text(
                            'View captured photo',
                            style: TextStyle(fontSize: 12),
                          ),
                          children: [
                            Image.memory(
                              _photoBytes!,
                              key: ValueKey(_photoRevision),
                              cacheWidth: 800,
                              height: 150,
                              errorBuilder: (_, _, _) => const Text(
                                'Photo unavailable. Capture the name again.',
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                        'Shop Match & Route Assignment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_matching &&
                    _name.text.trim().isNotEmpty &&
                    selected == null) ...[
                  Text(
                    options.isEmpty
                        ? 'Shop not found'
                        : exactMatches > 1
                        ? 'Choose the correct branch'
                        : 'Similar names found',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (options.isEmpty) _unknownShop(enabled),
                  for (final shop in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DispatchCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          enabled: enabled,
                          title: Text(
                            shop.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${shop.area}\n${shop.address.isEmpty ? shop.locationStatus : shop.address}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() {
                            _selectedId = shop.id;
                            _added = false;
                          }),
                        ),
                      ),
                    ),
                  if (options.isNotEmpty)
                    TextButton.icon(
                      onPressed: enabled ? () => _createShop() : null,
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Add new shop'),
                    ),
                ],
                if (selected != null)
                  DispatchCard(
                    key: const Key('dispatch-matched-shop'),
                    accent: DirectoryDesign.teal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DispatchBadge(
                          existing || _added
                              ? 'Scheduled for dispatch'
                              : 'Matched with Registered Shop',
                          icon: existing || _added
                              ? Icons.schedule_send_outlined
                              : Icons.verified_outlined,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          selected.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DispatchDropPoint(
                          shop: selected,
                          onCall: () => callShop(context, selected),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DispatchBadge(
                            selected.locationStatus,
                            icon: Icons.location_on_outlined,
                            color: selected.readyForDelivery
                                ? DirectoryDesign.teal
                                : const Color(0xffa66b12),
                          ),
                        ),
                        if (selected.hasMapsLink)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              'Google Maps location saved. Coordinates are not required.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: DirectoryDesign.muted,
                              ),
                            ),
                          )
                        else if (selected.hasCoordinates)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              selected.verified
                                  ? 'GPS entrance saved and verified.'
                                  : 'GPS pin needs entrance verification.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: DirectoryDesign.muted,
                              ),
                            ),
                          ),
                        if (selected.hasLocation)
                          TextButton.icon(
                            onPressed: _busy ? null : () => _preview(selected),
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: const Text('View location in Maps'),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              'Add a Google Maps link or capture the shop entrance location before scheduling the delivery.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: DirectoryDesign.muted,
                              ),
                            ),
                          ),
                        if (!selected.readyForDelivery)
                          OutlinedButton.icon(
                            onPressed: enabled
                                ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ShopForm(
                                        controller: c,
                                        shop: selected,
                                        locationService: widget.locationService,
                                      ),
                                    ),
                                  )
                                : null,
                            icon: const Icon(
                              Icons.edit_location_alt_outlined,
                              size: 18,
                            ),
                            label: const Text('Add or verify shop location'),
                          ),
                        if (existing || _added)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'This shop is already on this delivery list.',
                              style: TextStyle(
                                fontSize: 12,
                                color: DirectoryDesign.teal,
                              ),
                            ),
                          )
                        else ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey(c.drivers.map((d) => d.id).join('|')),
                            initialValue: c.drivers.any((d) => d.id == _driver)
                                ? _driver
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Delivery person',
                            ),
                            items: c.drivers
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text(d.name),
                                  ),
                                )
                                .toList(),
                            onChanged: enabled
                                ? (value) => setState(() => _driver = value)
                                : null,
                          ),
                          if (c.drivers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                'Create a delivery account before assigning this stop.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('confirm-dispatch'),
                            onPressed: canAdd ? _add : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: DirectoryDesign.navy,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(48, 46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.local_shipping_outlined,
                              size: 18,
                            ),
                            label: const Text('Confirm Dispatch'),
                          ),
                        ],
                        TextButton(
                          onPressed: enabled
                              ? () => setState(() => _selectedId = null)
                              : null,
                          child: const Text('Choose a different shop'),
                        ),
                      ],
                    ),
                  ),
                if (selected == null &&
                    _name.text.trim().isEmpty &&
                    !_busy &&
                    !_matching)
                  DispatchCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DispatchBadge(
                          _added ? 'Delivery saved' : 'Ready for a bill',
                          icon: _added
                              ? Icons.task_alt
                              : Icons.receipt_long_outlined,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _added
                              ? 'Scan the next bill to continue.'
                              : 'Scan or type a shop name to find its saved drop point.',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: DirectoryDesign.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _unknownShop(bool enabled) => DispatchCard(
    key: const Key('dispatch-unknown-shop'),
    accent: const Color(0xffffb95f),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DispatchBadge(
          'Unregistered Shop Detected',
          icon: Icons.help_outline,
          color: Color(0xff8b5a0a),
        ),
        const SizedBox(height: 10),
        Text(
          _name.text.trim(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        const Text(
          'This name is not in your shop directory. Add its contact details and save a Maps link or an entrance pin before dispatch.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: DirectoryDesign.muted,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: enabled ? () => _createShop() : null,
          style: FilledButton.styleFrom(
            backgroundColor: DirectoryDesign.teal,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.add_location_alt_outlined, size: 18),
          label: const Text('Add new shop'),
        ),
        OutlinedButton.icon(
          key: const Key('dispatch-direct-gps'),
          onPressed: enabled ? () => _createShop(captureLocation: true) : null,
          icon: const Icon(Icons.near_me_outlined, size: 18),
          label: const Text('Direct Live GPS Pin'),
        ),
        const Text(
          'Use live GPS while standing at the shop entrance. Review the shop details and confirm the pin before saving.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: DirectoryDesign.muted,
          ),
        ),
      ],
    ),
  );
}
