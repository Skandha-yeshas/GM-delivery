import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../application/delivery_controller.dart';
import '../data/collection_location_service.dart';
import '../domain/ledger.dart';
import 'common.dart';

class CollectionForm extends StatefulWidget {
  const CollectionForm({
    super.key,
    required this.controller,
    required this.shopId,
    this.stopId,
    this.kind = LedgerKind.bill,
    this.correction,
    this.locationService,
  });
  final DeliveryController controller;
  final String shopId;
  final String? stopId;
  final LedgerKind kind;
  final EffectiveLedgerEntry? correction;
  final CollectionLocationService? locationService;
  @override
  State<CollectionForm> createState() => _CollectionFormState();
}

class _CollectionFormState extends State<CollectionForm> {
  final _form = GlobalKey<FormState>();
  final _bill = TextEditingController(),
      _amount = TextEditingController(),
      _paid = TextEditingController(text: '0.00'),
      _reference = TextEditingController(),
      _note = TextEditingController(),
      _reason = TextEditingController();
  final _operation = const Uuid().v4();
  late LedgerKind _type;
  PaymentMode _mode = PaymentMode.credit;
  CollectionLocation _location = const CollectionLocation();
  bool _saving = false, _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.correction?.original.command.kind ?? widget.kind;
    final prior = widget.correction?.values;
    if (prior != null) {
      _bill.text = prior.billNumber;
      _amount.text = rupees(prior.billPaise, symbol: false);
      _paid.text = rupees(prior.collectedPaise, symbol: false);
      _mode = prior.mode;
      _reference.text = prior.reference;
      _note.text = prior.note;
    } else if (_type == LedgerKind.payment) {
      _mode = PaymentMode.cash;
    }
    if (widget.correction == null &&
        [LedgerKind.bill, LedgerKind.payment].contains(_type)) {
      unawaited(_capture());
    }
  }

  Future<void> _capture() async {
    setState(() => _capturing = true);
    final location =
        await (widget.locationService ?? DeviceCollectionLocationService())
            .capture();
    if (mounted) {
      setState(() {
        _location = location;
        _capturing = false;
      });
    }
  }

  @override
  void dispose() {
    for (final field in [_bill, _amount, _paid, _reference, _note, _reason]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = widget.controller;
      final stop = c.stops.where((s) => s.id == widget.stopId).firstOrNull;
      await c.submitLedger(
        LedgerCommand(
          operationId: _operation,
          shopId: widget.shopId,
          kind: widget.correction == null ? _type : LedgerKind.correction,
          capturedAt: DateTime.now().toUtc(),
          stopId: widget.correction?.original.command.stopId ?? widget.stopId,
          expectedStopVersion: stop?.version,
          legacyVisitOperationId: c.pending
              .where(
                (p) => p.stopId == stop?.id && p.status.name == 'delivered',
              )
              .firstOrNull
              ?.operationId,
          originalId: widget.correction?.original.id,
          expectedRevision: widget.correction?.latest.revision ?? 0,
          billNumber: _type == LedgerKind.bill ? _bill.text.trim() : '',
          billPaise: _type == LedgerKind.payment ? 0 : parsePaise(_amount.text),
          collectedPaise:
              _type == LedgerKind.opening || _mode == PaymentMode.credit
              ? 0
              : parsePaise(_paid.text),
          mode: _type == LedgerKind.opening ? PaymentMode.credit : _mode,
          reference: _reference.text.trim(),
          note: _note.text.trim(),
          reason: _reason.text.trim(),
          location: _location,
        ),
      );
      if (mounted) {
        showMessage(
          context,
          c.shared
              ? 'Saved on this phone. Check the collection sync status.'
              : 'Ledger entry saved on this phone.',
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = ledgerError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool money = false,
    int maxLength = 200,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      maxLength: maxLength,
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(labelText: label, counterText: ''),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Enter $label.';
        }
        if (money) {
          try {
            parsePaise(value ?? '');
          } on FormatException catch (e) {
            return e.message;
          }
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    int? remaining;
    try {
      remaining =
          parsePaise(_amount.text) -
          (_mode == PaymentMode.credit ? 0 : parsePaise(_paid.text));
    } on FormatException {
      /* Incomplete typed amount. */
    }
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.correction != null
                ? 'Correct ledger entry'
                : _type == LedgerKind.opening
                ? 'Opening balance'
                : 'Record collection',
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                c.shopFor(widget.shopId)?.name ?? 'Shop',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Outstanding: ${rupees(c.balanceFor(widget.shopId).balancePaise)}',
                style: const TextStyle(fontSize: 16),
              ),
              if (c.pendingLedger.any((p) => p.command.shopId == widget.shopId))
                const Text('Includes entries waiting to sync.'),
              const SizedBox(height: 20),
              if (widget.correction == null &&
                  widget.kind == LedgerKind.bill) ...[
                SegmentedButton<LedgerKind>(
                  segments: const [
                    ButtonSegment(
                      value: LedgerKind.bill,
                      label: Text('New bill'),
                    ),
                    ButtonSegment(
                      value: LedgerKind.payment,
                      label: Text('Old balance only'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: _saving
                      ? null
                      : (values) => setState(() {
                          _type = values.single;
                          if (_type == LedgerKind.payment &&
                              _mode == PaymentMode.credit) {
                            _mode = PaymentMode.cash;
                          }
                        }),
                ),
                const SizedBox(height: 20),
              ],
              if (_type == LedgerKind.bill)
                _text(_bill, 'Bill number', required: true, maxLength: 100),
              if (_type != LedgerKind.payment)
                _text(
                  _amount,
                  _type == LedgerKind.opening
                      ? 'Opening balance (₹)'
                      : 'Bill amount (₹)',
                  required: true,
                  money: true,
                  maxLength: 15,
                ),
              if (_type != LedgerKind.opening) ...[
                DropdownButtonFormField<PaymentMode>(
                  key: ValueKey('mode-$_type'),
                  initialValue: _mode,
                  decoration: const InputDecoration(labelText: 'Payment mode'),
                  items: [
                    for (final mode in PaymentMode.values)
                      if (_type != LedgerKind.payment ||
                          mode != PaymentMode.credit)
                        DropdownMenuItem(
                          value: mode,
                          child: Text(
                            mode == PaymentMode.credit
                                ? 'Credit — no payment'
                                : mode.name.toUpperCase(),
                          ),
                        ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _mode = value!;
                          if (_mode == PaymentMode.credit) _paid.text = '0.00';
                        }),
                ),
                const SizedBox(height: 16),
                if (_mode != PaymentMode.credit)
                  _text(
                    _paid,
                    'Amount collected (₹)',
                    required: true,
                    money: true,
                    maxLength: 15,
                  ),
                if (_mode == PaymentMode.upi || _mode == PaymentMode.cheque)
                  _text(
                    _reference,
                    _mode == PaymentMode.upi
                        ? 'UPI reference (optional)'
                        : 'Cheque number (optional)',
                  ),
                if (_type == LedgerKind.bill && remaining != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'This bill balance: ${rupees(remaining)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
              _text(_note, 'Note (optional)', maxLength: 1000),
              if (widget.correction != null) ...[
                const Text(
                  'The original stays in the audit history. Use zero amounts to reverse an entry; a payment reversal keeps its original payment mode.',
                ),
                const SizedBox(height: 12),
                _text(
                  _reason,
                  'Correction reason',
                  required: true,
                  maxLength: 500,
                ),
              ],
              if (widget.correction == null && _type != LedgerKind.opening) ...[
                Text(
                  _capturing
                      ? 'Capturing location…'
                      : _location.status == 'available'
                      ? 'Location captured · accuracy ${_location.accuracy!.round()} m'
                      : 'Location ${_location.status}. The collection can still be saved.',
                  style: const TextStyle(fontSize: 16),
                ),
                TextButton.icon(
                  onPressed: _saving || _capturing ? null : _capture,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Retry location capture'),
                ),
                const Text(
                  'Time is recorded when you save. UPI and cheque entries record the payment reported here; bank clearance is not checked.',
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                _saving
                    ? 'Saving…'
                    : widget.correction != null
                    ? 'Save correction'
                    : _type == LedgerKind.opening
                    ? 'Save opening balance'
                    : 'Save collection & mark delivered',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
