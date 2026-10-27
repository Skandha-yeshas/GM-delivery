import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../application/delivery_controller.dart';
import '../domain/models.dart';
import '../domain/route_order.dart';
import 'dispatch_design.dart';
import 'shop_directory.dart';

class OwnerRoutePlanner extends StatefulWidget {
  const OwnerRoutePlanner({
    super.key,
    required this.controller,
    required this.date,
    required this.onScan,
    required this.onAddStops,
    required this.onChooseDate,
    required this.stopBuilder,
    required this.onDraftChanged,
  });
  final DeliveryController controller;
  final DateTime date;
  final VoidCallback onScan, onAddStops, onChooseDate;
  final Widget Function(DeliveryStop, int) stopBuilder;
  final ValueChanged<bool> onDraftChanged;
  @override
  State<OwnerRoutePlanner> createState() => _OwnerRoutePlannerState();
}

class _OwnerRoutePlannerState extends State<OwnerRoutePlanner> {
  DeliveryController get c => widget.controller;
  String? _driverId;
  List<DeliveryStop> _baseline = [];
  List<String> _pendingIds = [];
  String _operationId = const Uuid().v4();
  bool _dirty = false, _saving = false;
  String? _error;

  List<DeliveryStop> get _current =>
      c.stopsFor(widget.date).where((s) => s.driverId == _driverId).toList();
  bool get _stale => !_command.matches(_current);
  bool get _locked =>
      _driverId != null &&
      c.isSettlementLocked(_driverId!, dateKey(widget.date));
  bool get _queued => _current.any((s) => c.pendingStopIds.contains(s.id));
  RouteOrderCommand get _command => RouteOrderCommand(
    operationId: _operationId,
    driverId: _driverId ?? '',
    date: dateKey(widget.date),
    expected: _baseline,
    pendingIds: _pendingIds,
  );

  @override
  void initState() {
    super.initState();
    _selectInitialDriver();
    _load();
  }

  void _selectInitialDriver() {
    _driverId =
        c.drivers
            .where(
              (d) => c.stopsFor(widget.date).any((s) => s.driverId == d.id),
            )
            .firstOrNull
            ?.id ??
        c.drivers.firstOrNull?.id;
  }

  void _load() {
    _baseline = List.of(_current);
    _pendingIds = _baseline
        .where((s) => s.status == VisitStatus.pending)
        .map((s) => s.id)
        .toList();
    _operationId = const Uuid().v4();
    _error = null;
  }

  @override
  void didUpdateWidget(covariant OwnerRoutePlanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_saving) {
      if (!c.drivers.any((d) => d.id == _driverId)) _selectInitialDriver();
      _load();
    }
  }

  void _move(int oldIndex, int newIndex) {
    if (c.busy || _saving || _locked || _queued || _stale) return;
    if (oldIndex == newIndex) return;
    setState(() {
      _pendingIds.insert(newIndex, _pendingIds.removeAt(oldIndex));
      _dirty =
          _pendingIds.join('|') !=
          _baseline
              .where((s) => s.status == VisitStatus.pending)
              .map((s) => s.id)
              .join('|');
      _operationId = const Uuid().v4();
      _error = null;
    });
    widget.onDraftChanged(_dirty);
  }

  void _reset() {
    setState(() {
      _dirty = false;
      _load();
    });
    widget.onDraftChanged(false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await c.saveRouteOrder(_command);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _load();
      });
      widget.onDraftChanged(false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            c.shared
                ? 'Route saved. The delivery person receives this order when they sync.'
                : 'Delivery order saved on this phone.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().contains('SocketException')
              ? 'Could not confirm the save. Keep this draft and retry, or reset and sync to check the saved order.'
              : errorText(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arranged = _baseline.isEmpty ? <DeliveryStop>[] : _command.arrange();
    final pending = _pendingIds
        .map((id) => arranged.firstWhere((s) => s.id == id))
        .toList();
    final finished = arranged
        .where((s) => s.status != VisitStatus.pending)
        .toList();
    final canMove = !c.busy && !_saving && !_locked && !_queued && !_stale;
    final canLeave = !_dirty && !_saving && !c.busy;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (!_dirty && !_saving) await c.refresh();
            },
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
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: DirectoryDesign.navy,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.route_rounded,
                                    color: Color(0xff89e7d0),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Delivery order',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          readableDate(widget.date),
                                          style: const TextStyle(
                                            color: Color(0xffd4def4),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: canLeave
                                        ? widget.onChooseDate
                                        : null,
                                    tooltip: 'Choose delivery date',
                                    style: IconButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      disabledForegroundColor: Colors.white54,
                                    ),
                                    icon: const Icon(
                                      Icons.calendar_month_outlined,
                                      size: 22,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${pending.length} remaining  •  ${finished.length} completed / attempted',
                                style: const TextStyle(
                                  color: Color(0xffd4def4),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (c.drivers.isEmpty)
                          const Text(
                            'Add a delivery account before preparing a route.',
                          )
                        else
                          DropdownButtonFormField<String>(
                            key: ValueKey('route-driver-$_driverId'),
                            initialValue: _driverId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Delivery person',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            items: c.drivers
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text(
                                      d.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: canLeave
                                ? (id) => setState(() {
                                    _driverId = id;
                                    _load();
                                  })
                                : null,
                          ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            FilledButton.icon(
                              onPressed: canLeave ? widget.onScan : null,
                              icon: const Icon(
                                Icons.document_scanner_outlined,
                                size: 18,
                              ),
                              label: const Text('Scan whole bill'),
                            ),
                            OutlinedButton.icon(
                              onPressed: canLeave ? widget.onAddStops : null,
                              icon: const Icon(Icons.playlist_add, size: 18),
                              label: Text(
                                arranged.isEmpty
                                    ? 'Prepare delivery list'
                                    : 'Add stops',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Delivery sequence',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_dirty)
                              const DispatchBadge(
                                'Unsaved',
                                color: Color(0xffa66b12),
                              )
                            else
                              const DispatchBadge(
                                'Saved',
                                icon: Icons.check_circle_outline,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Drag the handle or use the arrows. Save the order before the driver leaves.',
                          style: TextStyle(
                            fontSize: 12,
                            color: DirectoryDesign.muted,
                            height: 1.5,
                          ),
                        ),
                        if (_locked || _queued || (_dirty && _stale))
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _locked
                                  ? 'Settlement submitted or approved. Reopen the day to edit this route.'
                                  : _queued
                                  ? 'Sync pending delivery and collection records before reordering.'
                                  : 'This route has changed. Reset the draft, then sync to review it.',
                              style: const TextStyle(
                                color: Color(0xff995600),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (arranged.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
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
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Scan a bill or choose saved shops to prepare this delivery list.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverReorderableList(
                    itemCount: pending.length,
                    onReorderItem: _move,
                    itemBuilder: (context, index) {
                      final stop = pending[index];
                      return Padding(
                        key: ValueKey('route-stop-${stop.id}'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _card(
                          stop,
                          first: index == 0,
                          controls: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: ValueKey('route-up-${stop.id}'),
                                tooltip: 'Move up',
                                onPressed: canMove && index > 0
                                    ? () => _move(index, index - 1)
                                    : null,
                                icon: const Icon(Icons.keyboard_arrow_up),
                              ),
                              IconButton(
                                key: ValueKey('route-down-${stop.id}'),
                                tooltip: 'Move down',
                                onPressed: canMove && index < pending.length - 1
                                    ? () => _move(index, index + 1)
                                    : null,
                                icon: const Icon(Icons.keyboard_arrow_down),
                              ),
                              ReorderableDragStartListener(
                                key: ValueKey('route-drag-${stop.id}'),
                                index: index,
                                enabled: canMove,
                                child: Semantics(
                                  label: 'Drag to reorder',
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: canMove
                                          ? DirectoryDesign.navy
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (finished.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Completed & attempted · positions kept',
                        style: TextStyle(
                          color: DirectoryDesign.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: finished.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _card(finished[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (arranged.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xffe1e2e8))),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Reset draft',
                  key: const Key('route-reset'),
                  onPressed: _dirty && !_saving && !c.busy ? _reset : null,
                  icon: const Icon(Icons.restart_alt),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('route-save'),
                    onPressed: _dirty && canMove ? _save : null,
                    icon: Icon(
                      _saving
                          ? Icons.hourglass_top
                          : Icons.check_circle_outline,
                      size: 19,
                    ),
                    label: Text(
                      _saving
                          ? 'Saving order…'
                          : _dirty
                          ? 'Save delivery order'
                          : 'Delivery order saved',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _card(DeliveryStop stop, {bool first = false, Widget? controls}) {
    final shop = c.shopFor(stop.shopId);
    return DispatchCard(
      accent: first ? DirectoryDesign.navy : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: first
                    ? DirectoryDesign.navy
                    : const Color(0xffeef0f5),
                foregroundColor: first ? Colors.white : DirectoryDesign.navy,
                child: Text(
                  '${stop.order}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (controls != null) ...[const SizedBox(height: 4), controls],
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (first)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'FIRST REMAINING DROP',
                      style: TextStyle(
                        fontSize: 9,
                        color: DirectoryDesign.teal,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                Text(
                  shop?.name ?? 'Shop unavailable',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (shop?.contactName.isNotEmpty ?? false)
                  Text(
                    shop!.contactName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DirectoryDesign.muted,
                    ),
                  ),
                const SizedBox(height: 8),
                if (shop != null)
                  Text(
                    shop.address.isNotEmpty ? shop.address : shop.area,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: DirectoryDesign.muted,
                    ),
                  ),
                const SizedBox(height: 8),
                DispatchBadge(
                  stop.status == VisitStatus.pending
                      ? (shop?.hasMapsLink ?? false)
                            ? 'Maps link saved'
                            : (shop?.readyForDelivery ?? false)
                            ? 'Entrance pin saved'
                            : 'Add delivery location'
                      : stop.status.label,
                  icon: stop.status == VisitStatus.pending
                      ? Icons.location_on_outlined
                      : Icons.task_alt,
                ),
                ExpansionTile(
                  key: ValueKey('route-details-${stop.id}'),
                  tilePadding: EdgeInsets.zero,
                  minTileHeight: 40,
                  title: const Text(
                    'Details & delivery actions',
                    style: TextStyle(fontSize: 11),
                  ),
                  children: [
                    if (_dirty || _saving)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Save or reset the order to use delivery actions.',
                          style: TextStyle(fontSize: 12),
                        ),
                      )
                    else
                      widget.stopBuilder(stop, stop.order),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
