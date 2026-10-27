part of 'cloud_service.dart';

class LedgerSnapshot {
  const LedgerSnapshot(this.entries, this.balances);
  final List<LedgerEntry> entries;
  final List<CreditBalance> balances;
}

class LedgerReceipt {
  const LedgerReceipt(this.entry, this.balance);
  final LedgerEntry entry;
  final CreditBalance balance;
}

extension LedgerCloud on CloudService {
  Future<LedgerSnapshot> _ledgerSnapshot() async {
    final entries = (await _allRows(
      'ledger_events',
      'sequence',
    )).map(LedgerEntry.fromMap).toList();
    final balances = <CreditBalance>[];
    for (var offset = 0; ; offset += 500) {
      final page =
          await client.rpc(
                'ledger_balances',
                params: {'p_offset': offset, 'p_limit': 500},
              )
              as List;
      balances.addAll(
        page.map(
          (r) => CreditBalance.fromMap(Map<String, dynamic>.from(r as Map)),
        ),
      );
      if (page.length < 500) break;
    }
    return LedgerSnapshot(entries, balances);
  }

  Future<LedgerReceipt> _sendLedger(LedgerCommand command) async {
    final result = Map<String, dynamic>.from(
      await client.rpc('record_ledger', params: {'p_payload': command.toMap()})
          as Map,
    );
    return LedgerReceipt(
      LedgerEntry.fromMap(Map<String, dynamic>.from(result['entry'] as Map)),
      CreditBalance.fromMap(
        Map<String, dynamic>.from(result['balance'] as Map),
      ),
    );
  }
}
