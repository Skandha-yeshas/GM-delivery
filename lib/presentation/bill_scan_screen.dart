import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../application/delivery_controller.dart';
import '../data/bill_scan_service.dart';
import '../domain/bill_shop_matcher.dart';
import '../domain/models.dart';
import 'common.dart';
import 'shop_form.dart';
import 'workspace_design.dart';

class BillScanScreen extends StatefulWidget {
  const BillScanScreen({
    super.key,
    required this.controller,
    required this.date,
    this.scanner,
  });
  final DeliveryController controller;
  final DateTime date;
  final BillScanService? scanner;
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

  Future<void> _createShop() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    String? savedId;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShopForm(
          controller: c,
          initialName: name,
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
      final canAdd =
          !_busy &&
          !_matching &&
          !c.busy &&
          !_added &&
          !existing &&
          selected?.readyForDelivery == true &&
          c.drivers.any((d) => d.id == _driver);
      final enabled = !_busy && !_matching && !c.busy;
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Scan shop name')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(
                children: [
                  const Expanded(child: WorkspaceLabel('Prepare a delivery')),
                  WorkspaceBadge(
                    readableDate(widget.date),
                    icon: Icons.calendar_today_outlined,
                    color: WorkspaceColors.ink,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _step('1', 'Capture', _name.text.isEmpty),
                  const Expanded(child: Divider(indent: 8, endIndent: 8)),
                  _step(
                    '2',
                    'Find shop',
                    _name.text.isNotEmpty && selected == null,
                  ),
                  const Expanded(child: Divider(indent: 8, endIndent: 8)),
                  _step('3', 'Add', selected != null),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: WorkspaceColors.ink,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xff7bc9ba),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.document_scanner_outlined,
                        size: 30,
                        color: Color(0xff9ddbd0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'One bill. One shop.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Photograph the whole bill.\nWe’ll extract only the customer’s shop name.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xffbecddd),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: enabled
                            ? () => _pick(ImageSource.camera)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff6de0c4),
                          foregroundColor: WorkspaceColors.ink,
                        ),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          _busy ? 'Reading shop name…' : 'Scan whole bill',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: enabled
                          ? () => _pick(ImageSource.gallery)
                          : null,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xffd8e7ef),
                      ),
                      icon: const Icon(Icons.photo_library_outlined, size: 17),
                      label: const Text('Choose a photo'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              WorkspaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WorkspaceLabel('Shop name'),
                    const SizedBox(height: 12),
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
                        style: TextStyle(
                          fontSize: 11,
                          color: WorkspaceColors.muted,
                        ),
                      ),
                      Wrap(
                        spacing: 6,
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
                        padding: EdgeInsets.only(top: 14),
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
                            color: _added
                                ? WorkspaceColors.teal
                                : WorkspaceColors.muted,
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
              const SizedBox(height: 18),
              if (!_matching &&
                  _name.text.trim().isNotEmpty &&
                  selected == null) ...[
                Row(
                  children: [
                    Icon(
                      options.isEmpty
                          ? Icons.search_off_rounded
                          : Icons.storefront_outlined,
                      size: 20,
                      color: WorkspaceColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        options.isEmpty
                            ? 'Shop not found'
                            : exactMatches > 1
                            ? 'Choose the correct branch'
                            : 'Similar names found',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: WorkspaceColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              for (final shop in options)
                if (selected == null || selected.id != shop.id)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: WorkspaceCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        enabled: enabled,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xffe8f5f1),
                          child: Text(
                            shop.name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: WorkspaceColors.teal,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          shop.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${shop.area}\n${shop.address.isEmpty ? shop.locationStatus : shop.address}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => setState(() {
                          _selectedId = shop.id;
                          _added = false;
                        }),
                      ),
                    ),
                  ),
              if (selected == null &&
                  _name.text.trim().isNotEmpty &&
                  !_matching)
                WorkspaceCard(
                  color: const Color(0xffedf6f3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New to your directory?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: WorkspaceColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Add the shop here and continue preparing this delivery.',
                        style: TextStyle(
                          fontSize: 12,
                          color: WorkspaceColors.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: enabled ? _createShop : null,
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Add new shop'),
                        ),
                      ),
                    ],
                  ),
                ),
              if (selected != null) ...[
                WorkspaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WorkspaceBadge(
                        _added ? 'Added to delivery list' : 'Shop found',
                        icon: Icons.check_circle_outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        selected.name,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                          color: WorkspaceColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          selected.area,
                          selected.address,
                        ].where((v) => v.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          color: WorkspaceColors.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      WorkspaceBadge(
                        selected.locationStatus,
                        color: selected.readyForDelivery
                            ? WorkspaceColors.teal
                            : WorkspaceColors.amber,
                        icon: Icons.location_on_outlined,
                      ),
                      if (selected.hasMapsLink) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Google Maps location saved. Coordinates are not required.',
                          style: TextStyle(
                            fontSize: 12,
                            color: WorkspaceColors.muted,
                          ),
                        ),
                      ],
                      if (selected.hasCoordinates) ...[
                        const SizedBox(height: 16),
                        const WorkspaceLabel('Saved entrance coordinates'),
                        const SizedBox(height: 8),
                        SelectableText(
                          'GPS: ${selected.latitude!.toStringAsFixed(6)}, ${selected.longitude!.toStringAsFixed(6)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: WorkspaceColors.ink,
                          ),
                        ),
                      ],
                      if (selected.hasLocation)
                        TextButton.icon(
                          onPressed: _busy ? null : () => _preview(selected),
                          icon: const Icon(Icons.map_outlined, size: 17),
                          label: const Text('View location in Maps'),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Add a Google Maps link or capture the shop entrance location before scheduling the delivery.',
                            style: TextStyle(
                              color: WorkspaceColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (!selected.readyForDelivery)
                        OutlinedButton.icon(
                          onPressed: enabled
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ShopForm(controller: c, shop: selected),
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: const Text('Add or verify shop location'),
                        ),
                      if (existing || _added)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'This shop is already on this delivery list.',
                            style: TextStyle(
                              fontSize: 12,
                              color: WorkspaceColors.teal,
                            ),
                          ),
                        ),
                      if (!_added)
                        TextButton(
                          onPressed: enabled
                              ? () => setState(() => _selectedId = null)
                              : null,
                          child: const Text('Choose a different shop'),
                        ),
                    ],
                  ),
                ),
                if (!_added && !existing) ...[
                  const SizedBox(height: 14),
                  WorkspaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const WorkspaceLabel('Assign delivery'),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          key: ValueKey(c.drivers.map((d) => d.id).join('|')),
                          initialValue: c.drivers.any((d) => d.id == _driver)
                              ? _driver
                              : null,
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
                              style: TextStyle(
                                fontSize: 12,
                                color: WorkspaceColors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(
                  'View delivery list (${c.stopsFor(widget.date).length})',
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              color: Colors.white,
              child: FilledButton.icon(
                onPressed: _added && enabled
                    ? () => _pick(ImageSource.camera)
                    : canAdd
                    ? _add
                    : null,
                icon: Icon(
                  _added
                      ? Icons.document_scanner_outlined
                      : Icons.playlist_add_check,
                ),
                label: Text(
                  _added ? 'Scan next shop' : 'Confirm shop & add delivery',
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _step(String number, String text, bool active) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 11,
        backgroundColor: active
            ? WorkspaceColors.teal
            : const Color(0xffe4e9f0),
        child: Text(
          number,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : WorkspaceColors.muted,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: active ? WorkspaceColors.ink : WorkspaceColors.muted,
        ),
      ),
    ],
  );
}
