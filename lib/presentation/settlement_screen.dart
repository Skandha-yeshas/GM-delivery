import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../application/delivery_controller.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/settlement.dart';
import 'common.dart';

class SettlementsScreen extends StatelessWidget {
  const SettlementsScreen({super.key, required this.controller});
  final DeliveryController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final keys = <String, (String, String)>{};
      void add(String driver, String date) {
        if (c.isOwner || driver == c.accountId) {
          keys['$driver:$date'] = (driver, date);
        }
      }

      for (final s in c.stops) {
        add(s.driverId, s.date);
      }
      for (final d in c.settlements) {
        add(d.driverId, d.date);
      }
      if (!c.isOwner) add(c.accountId, dateKey(DateTime.now()));
      final days = keys.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
      return Scaffold(
        appBar: AppBar(
          title: const Text('Daily settlements'),
          actions: [
            if (c.shared)
              IconButton(
                tooltip: 'Sync settlements',
                onPressed: c.busy ? null : () => runAction(context, c.refresh),
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              c.isOwner ? 'Review cash handed over' : 'Close your delivery day',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Totals follow the delivery-list date. Submitting locks that day’s collections until an owner reopens it.',
            ),
            if (c.settlementSyncError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  c.settlementSyncError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            if (days.isEmpty)
              const Text('Prepare a delivery list to start a settlement.'),
            for (final key in days)
              Builder(
                builder: (context) {
                  final day = c.settlementFor(key.$1, key.$2);
                  final pending = c.pendingSettlements.any(
                    (p) =>
                        p.command.driverId == key.$1 &&
                        p.command.date == key.$2,
                  );
                  final name =
                      c.profiles
                          .where((p) => p.id == key.$1)
                          .firstOrNull
                          ?.name ??
                      'Delivery person';
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Icon(
                        day.status == 'Approved'
                            ? Icons.verified_outlined
                            : Icons.receipt_long_outlined,
                      ),
                      title: Text('${key.$2} · $name'),
                      subtitle: Text(
                        '${pending ? 'Awaiting sync' : day.status}\nCash recorded ${rupees(day.totals.cash)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettlementScreen(
                            controller: c,
                            driverId: key.$1,
                            date: key.$2,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({
    super.key,
    required this.controller,
    required this.driverId,
    required this.date,
  });
  final DeliveryController controller;
  final String driverId, date;
  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  final _amount = TextEditingController(), _reason = TextEditingController();
  bool _saving = false;
  String? _draftError;
  DeliveryController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(_loadDraft());
  }

  Future<void> _loadDraft() async {
    final text = await c.store.getSetting(
      'settlement-draft:${widget.driverId}:${widget.date}',
    );
    if (!mounted ||
        text == null ||
        _amount.text.isNotEmpty ||
        _reason.text.isNotEmpty) {
      return;
    }
    final map = jsonDecode(text) as Map;
    setState(() {
      _amount.text = map['amount'] as String;
      _reason.text = map['reason'] as String;
    });
  }

  Future<void> _saveDraft() async {
    setState(() {});
    try {
      await c.saveSettlementDraft(
        widget.driverId,
        widget.date,
        _amount.text,
        _reason.text,
      );
      if (mounted && _draftError != null) setState(() => _draftError = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _draftError =
              'Draft could not be saved on this phone. Try again before leaving.',
        );
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _act(SettlementAction action, {String? reason}) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final day = c.settlementFor(widget.driverId, widget.date);
      await c.submitSettlement(
        SettlementCommand(
          operationId: const Uuid().v4(),
          driverId: widget.driverId,
          date: widget.date,
          action: action,
          expectedRevision: day.revision,
          ledgerVersion: day.totals.ledgerVersion,
          capturedAt: DateTime.now().toUtc(),
          handedPaise: action == SettlementAction.submit
              ? parsePaise(_amount.text)
              : day.latest?.command.handedPaise ?? 0,
          reason: reason ?? _reason.text,
        ),
      );
      if (mounted) {
        showMessage(
          context,
          c.shared
              ? 'Saved on phone. Waiting for server receipt.'
              : 'Settlement ${action.name} saved.',
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, settlementError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approve(SettlementDay day) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm cash received'),
        content: Text(
          'Approve only after counting ${rupees(day.latest!.command.handedPaise)} received from the delivery person. This confirms the submitted cash difference of ${rupees(day.latest!.command.handedPaise - day.totals.cash)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm & approve'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _act(
        SettlementAction.approve,
        reason: 'Owner confirmed the submitted cash handover.',
      );
    }
  }

  Future<void> _reopen() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReopenReasonDialog(),
    );
    if (reason != null && mounted) {
      await _act(SettlementAction.reopen, reason: reason);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final day = c.settlementFor(widget.driverId, widget.date);
      final t = day.totals;
      final pending = c.pendingSettlements
          .where(
            (p) =>
                p.command.driverId == widget.driverId &&
                p.command.date == widget.date,
          )
          .firstOrNull;
      final submitted = day.events
          .where((e) => e.command.action == SettlementAction.submit)
          .lastOrNull;
      final declarationLocked =
          day.locked || (pending != null && !pending.rejected);
      final declaration =
          pending != null &&
              !pending.rejected &&
              pending.command.action == SettlementAction.submit
          ? pending.command
          : submitted?.command;
      int? entered;
      try {
        entered = parsePaise(_amount.text);
      } catch (_) {}
      final handed = declarationLocked ? declaration?.handedPaise : entered;
      final difference = handed == null ? null : handed - t.cash;
      final canSubmit =
          !c.isOwner &&
          c.accountId == widget.driverId &&
          !day.locked &&
          c.pendingCount == 0 &&
          !_saving &&
          entered != null &&
          (difference == 0 || _reason.text.trim().isNotEmpty) &&
          (!c.shared ||
              c.settlements.any(
                (d) => d.driverId == widget.driverId && d.date == widget.date,
              ));
      Widget total(String label, int value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              rupees(value),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('Day settlement'),
          actions: [
            if (c.shared)
              IconButton(
                tooltip: 'Sync settlements',
                onPressed: c.busy ? null : () => runAction(context, c.refresh),
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
          children: [
            Text(
              widget.date,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              c.profiles
                      .where((p) => p.id == widget.driverId)
                      .firstOrNull
                      ?.name ??
                  'Delivery person',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(day.locked ? Icons.lock_outline : Icons.lock_open),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pending != null
                            ? (pending.rejected
                                  ? 'Request rejected — review changes'
                                  : 'Saved on phone · awaiting receipt')
                            : day.status,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (c.shared)
              const Text(
                'Last synced totals. Sync before reviewing cash. Offline drafts are saved on this phone.',
              ),
            if (c.settlementSyncError != null)
              Text(
                c.settlementSyncError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            total('Bills recorded', t.bills),
            total('Old-balance payments', t.oldPayments),
            total('Credit given on bills', t.credit),
            total('UPI recorded', t.upi),
            total('Cheques recorded', t.cheque),
            const Divider(),
            total('Expected cash from ledger', t.expectedCash),
            total('Cash recorded', t.cash),
            const Text(
              'Expected cash = bills + old-balance payments − credit − UPI − cheques. UPI and cheques are reported receipts, not bank clearance.',
            ),
            const SizedBox(height: 20),
            if (declarationLocked) ...[
              total(
                'Cash handed over (reported)',
                declaration?.handedPaise ?? 0,
              ),
              if (declaration?.reason.isNotEmpty ?? false)
                Text('Driver’s explanation: ${declaration!.reason}'),
              const Text(
                'Collections are locked. An owner must reopen this day before any correction or additional collection.',
              ),
            ] else if (!c.isOwner) ...[
              TextField(
                key: const Key('settlement-cash'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cash physically handed over (₹)',
                  helperText:
                      'Total for this day, including earlier handovers. Enter 0 if none.',
                  helperMaxLines: 2,
                ),
                onChanged: (_) => unawaited(_saveDraft()),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('settlement-reason'),
                controller: _reason,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: difference != null && difference != 0
                      ? 'Cash difference reason (required)'
                      : 'Note (optional)',
                ),
                onChanged: (_) => unawaited(_saveDraft()),
              ),
              if (_draftError != null) Text(_draftError!),
            ],
            if (difference != null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: difference == 0
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      difference == 0
                          ? 'Cash matches'
                          : difference < 0
                          ? 'Cash shortage'
                          : 'Extra cash handed over',
                    ),
                    Text(
                      rupees(difference),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Text('Handed over minus cash recorded'),
                  ],
                ),
              ),
            if (c.pendingCount > 0) ...[
              Text(
                'Sync required · ${c.pendingCount} pending operations',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Settlement is blocked until every pending operation on this phone has a receipt.',
              ),
              for (final detail in c.pendingOperationDetails)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(detail),
                  ),
                ),
              if (c.shared)
                OutlinedButton.icon(
                  onPressed: c.busy
                      ? null
                      : () => runAction(context, c.refresh),
                  icon: const Icon(Icons.sync),
                  label: const Text('Retry synchronization'),
                ),
            ],
            if (pending?.rejected ?? false)
              OutlinedButton(
                onPressed: () => runAction(
                  context,
                  () =>
                      c.discardRejectedSettlement(pending!.command.operationId),
                ),
                child: const Text('Remove rejected request & review'),
              ),
            if (!c.isOwner && !day.locked)
              FilledButton.icon(
                key: const Key('settlement-submit'),
                onPressed: canSubmit
                    ? () => _act(SettlementAction.submit)
                    : null,
                icon: const Icon(Icons.lock_outline),
                label: Text(_saving ? 'Saving…' : 'Submit & lock day'),
              ),
            if (c.isOwner && day.locked) ...[
              if (day.latest?.command.action == SettlementAction.submit)
                FilledButton(
                  onPressed: c.pendingCount > 0 || _saving
                      ? null
                      : () => _approve(day),
                  child: const Text('Confirm cash received & approve'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: c.pendingCount > 0 || _saving ? null : _reopen,
                child: const Text('Reopen with reason'),
              ),
            ],
            if (c.isOwner && !day.locked)
              const Text(
                'The delivery person submits the day first. Owners then confirm cash received and approve.',
              ),
            if (day.events.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Settlement history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final e in day.events.reversed)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.command.action.name.toUpperCase()} · revision ${e.revision}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${c.profiles.where((p) => p.id == e.actorId).firstOrNull?.name ?? e.actorId} · ${e.recordedAt.toLocal()}',
                        ),
                        Text(
                          'Cash recorded ${rupees(e.totals.cash)} · handed over ${rupees(e.command.handedPaise)}',
                        ),
                        if (e.command.reason.isNotEmpty) Text(e.command.reason),
                        SelectableText(
                          'ID: ${e.command.operationId}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class _ReopenReasonDialog extends StatefulWidget {
  const _ReopenReasonDialog();
  @override
  State<_ReopenReasonDialog> createState() => _ReopenReasonDialogState();
}

class _ReopenReasonDialogState extends State<_ReopenReasonDialog> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reopen this day'),
    content: TextField(
      controller: input,
      autofocus: true,
      maxLength: 500,
      maxLines: 3,
      decoration: const InputDecoration(labelText: 'Required reason'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: input.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, input.text.trim()),
        child: const Text('Reopen day'),
      ),
    ],
  );
}
