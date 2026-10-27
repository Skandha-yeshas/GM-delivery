part of 'cloud_service.dart';

extension SettlementCloud on CloudService {
  Future<List<SettlementDay>> _settlementSnapshot() async {
    final result = <SettlementDay>[];
    for (var offset = 0; ; offset += 500) {
      final page =
          await client.rpc(
                'settlement_snapshot',
                params: {'p_offset': offset, 'p_limit': 500},
              )
              as List;
      result.addAll(
        page.map(
          (r) => SettlementDay.fromMap(Map<String, dynamic>.from(r as Map)),
        ),
      );
      if (page.length < 500) return result;
    }
  }

  Future<SettlementDay> _sendSettlement(SettlementCommand c) async =>
      SettlementDay.fromMap(
        Map<String, dynamic>.from(
          await client.rpc(
                'record_settlement',
                params: {'p_payload': c.toMap()},
              )
              as Map,
        ),
      );
}
