class PointsBalance {
  const PointsBalance({
    required this.freeRemainingPerFeature,
    required this.paidPoints,
  });

  final Map<String, int> freeRemainingPerFeature;
  final int paidPoints;

  factory PointsBalance.fromJson(Map<String, dynamic> json) {
    final rawFree = json['free_remaining_per_feature'];
    return PointsBalance(
      freeRemainingPerFeature: rawFree is Map
          ? rawFree.map((key, value) => MapEntry(
                key.toString(),
                value is int ? value : int.tryParse(value.toString()) ?? 0,
              ))
          : const <String, int>{},
      paidPoints: json['paid_points'] is int
          ? json['paid_points'] as int
          : int.tryParse(json['paid_points']?.toString() ?? '') ?? 0,
    );
  }
}

class PointsLedgerEntry {
  const PointsLedgerEntry({
    required this.id,
    required this.delta,
    required this.reason,
    this.refKey,
    this.refId,
    required this.balancePaidAfter,
    required this.freeUsed,
    this.freeRemainingAfter,
    this.memo,
    this.createdAt,
  });

  final int id;
  final int delta;
  final String reason;
  final String? refKey;
  final String? refId;
  final int balancePaidAfter;
  final int freeUsed;
  final int? freeRemainingAfter;
  final String? memo;
  final DateTime? createdAt;

  factory PointsLedgerEntry.fromJson(Map<String, dynamic> json) {
    return PointsLedgerEntry(
      id: _asInt(json['id']),
      delta: _asInt(json['delta']),
      reason: json['reason']?.toString() ?? '',
      refKey: json['ref_key']?.toString(),
      refId: json['ref_id']?.toString(),
      balancePaidAfter: _asInt(json['balance_paid_after']),
      freeUsed: _asInt(json['free_used']),
      freeRemainingAfter: json['free_remaining_after'] == null
          ? null
          : _asInt(json['free_remaining_after']),
      memo: json['memo']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class CostPreview {
  const CostPreview({
    required this.featureKey,
    required this.cost,
    required this.freeRemaining,
    required this.willUseFree,
    required this.paidPoints,
    required this.paidRemainingAfter,
    required this.sufficient,
  });

  final String featureKey;
  final int cost;
  final int freeRemaining;
  final bool willUseFree;
  final int paidPoints;
  final int paidRemainingAfter;
  final bool sufficient;

  factory CostPreview.fromJson(Map<String, dynamic> json) {
    return CostPreview(
      featureKey: json['feature_key']?.toString() ?? '',
      cost: _asInt(json['cost']),
      freeRemaining: _asInt(json['free_remaining']),
      willUseFree: json['will_use_free'] == true,
      paidPoints: _asInt(json['paid_points']),
      paidRemainingAfter: _asInt(json['paid_remaining_after']),
      sufficient: json['sufficient'] == true,
    );
  }
}

class RedeemResult {
  const RedeemResult({
    required this.credited,
    required this.newPaidBalance,
    this.codeMemo,
  });

  final int credited;
  final int newPaidBalance;
  final String? codeMemo;

  factory RedeemResult.fromJson(Map<String, dynamic> json) {
    return RedeemResult(
      credited: _asInt(json['credited']),
      newPaidBalance: _asInt(json['new_paid_balance']),
      codeMemo: json['code_memo']?.toString(),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
