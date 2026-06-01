import 'dart:convert';

import '../constants/api_constants.dart';
import '../models/points.dart';
import 'auth_service.dart';

class PointsService {
  const PointsService({AuthService? authService})
      : _authService = authService ?? const _DefaultAuthServiceProvider();

  final Object _authService;

  AuthService get _auth {
    final candidate = _authService;
    if (candidate is AuthService) return candidate;
    return AuthService();
  }

  Future<PointsBalance> fetchBalance() async {
    final response = await _auth.authenticatedRequest(
      'GET',
      ApiConstants.pointsMe,
    );
    _throwIfFailed(response.statusCode, response.body);
    return PointsBalance.fromJson(_decodeMap(response.body));
  }

  Future<List<PointsLedgerEntry>> fetchLedger({
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(ApiConstants.pointsLedger).replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final response = await _auth.authenticatedRequest('GET', uri.toString());
    _throwIfFailed(response.statusCode, response.body);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PointsLedgerEntry.fromJson)
          .toList();
    }
    return const <PointsLedgerEntry>[];
  }

  Future<CostPreview> previewCost(String featureKey) async {
    final response = await _auth.authenticatedRequest(
      'POST',
      ApiConstants.pointsPreview(featureKey),
    );
    _throwIfFailed(response.statusCode, response.body);
    return CostPreview.fromJson(_decodeMap(response.body));
  }

  Future<RedeemResult> redeem(String code) async {
    final response = await _auth.authenticatedRequest(
      'POST',
      ApiConstants.pointsRedeem,
      body: {'code': code},
    );
    _throwIfFailed(response.statusCode, response.body);
    return RedeemResult.fromJson(_decodeMap(response.body));
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('响应格式错误');
  }

  void _throwIfFailed(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        throw Exception(
          (decoded['message'] ?? decoded['error'] ?? '请求失败').toString(),
        );
      }
    } catch (_) {
      // Fall through to generic message.
    }
    throw Exception('请求失败 ($statusCode)');
  }
}

class _DefaultAuthServiceProvider {
  const _DefaultAuthServiceProvider();
}
