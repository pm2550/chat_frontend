import 'package:chat_app/models/points.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PointsBalance', () {
    test('parses paid points and per-feature free quota', () {
      final balance = PointsBalance.fromJson({
        'paid_points': '47',
        'free_remaining_per_feature': {
          'ai_image_gen': 3,
          'bot_invoke_official': '12',
        },
      });

      expect(balance.paidPoints, 47);
      expect(balance.freeRemainingPerFeature['ai_image_gen'], 3);
      expect(balance.freeRemainingPerFeature['bot_invoke_official'], 12);
    });

    test('falls back to empty values on malformed payloads', () {
      final balance = PointsBalance.fromJson({
        'paid_points': 'not-a-number',
        'free_remaining_per_feature': 'unexpected',
      });

      expect(balance.paidPoints, 0);
      expect(balance.freeRemainingPerFeature, isEmpty);
    });
  });

  group('PointsLedgerEntry', () {
    test('parses ledger metadata and timestamp', () {
      final entry = PointsLedgerEntry.fromJson({
        'id': '9',
        'delta': -10,
        'reason': 'feature_debit',
        'ref_key': 'ai_image_gen',
        'ref_id': 'task-1',
        'balance_paid_after': '37',
        'free_used': 0,
        'free_remaining_after': '0',
        'memo': 'AI 出图',
        'created_at': '2026-05-30T08:15:00',
      });

      expect(entry.id, 9);
      expect(entry.delta, -10);
      expect(entry.reason, 'feature_debit');
      expect(entry.refKey, 'ai_image_gen');
      expect(entry.refId, 'task-1');
      expect(entry.balancePaidAfter, 37);
      expect(entry.freeRemainingAfter, 0);
      expect(entry.createdAt, DateTime(2026, 5, 30, 8, 15));
    });
  });

  group('CostPreview', () {
    test('parses free preview state', () {
      final preview = CostPreview.fromJson({
        'feature_key': 'test_debit',
        'cost': 1,
        'free_remaining': 2,
        'will_use_free': true,
        'paid_points': 8,
        'paid_remaining_after': 8,
        'sufficient': true,
      });

      expect(preview.featureKey, 'test_debit');
      expect(preview.willUseFree, isTrue);
      expect(preview.sufficient, isTrue);
      expect(preview.freeRemaining, 2);
    });

    test('parses paid preview state', () {
      final preview = CostPreview.fromJson({
        'feature_key': 'ai_image_gen',
        'cost': '10',
        'free_remaining': 0,
        'will_use_free': false,
        'paid_points': '47',
        'paid_remaining_after': '37',
        'sufficient': true,
      });

      expect(preview.cost, 10);
      expect(preview.paidPoints, 47);
      expect(preview.paidRemainingAfter, 37);
      expect(preview.willUseFree, isFalse);
    });
  });

  test('RedeemResult parses credited balance response', () {
    final result = RedeemResult.fromJson({
      'credited': '100',
      'new_paid_balance': 140,
      'code_memo': 'manual top-up',
    });

    expect(result.credited, 100);
    expect(result.newPaidBalance, 140);
    expect(result.codeMemo, 'manual top-up');
  });
}
