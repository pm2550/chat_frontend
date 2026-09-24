import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/points.dart';
import '../models/user.dart';
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
    _throwIfFailed(response);
    return PointsBalance.fromJson(_decodeMap(response));
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
    _throwIfFailed(response);
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
    _throwIfFailed(response);
    return CostPreview.fromJson(_decodeMap(response));
  }

  Future<RedeemResult> redeem(String code) async {
    final response = await _auth.authenticatedRequest(
      'POST',
      ApiConstants.pointsRedeem,
      body: {'code': code},
    );
    _throwIfFailed(response);
    return RedeemResult.fromJson(_decodeMap(response));
  }

  Future<List<User>> searchUsers(String keyword, {int limit = 10}) async {
    if (keyword.trim().isEmpty) return const [];
    final uri = Uri.parse(ApiConstants.profileSearch).replace(
      queryParameters: {
        'keyword': keyword.trim(),
        'limit': '$limit',
      },
    );
    final response = await _auth.authenticatedRequest('GET', uri.toString());
    _throwIfFailed(response);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rawList =
        _extractList(decoded, keys: const ['data', 'users', 'content']);
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(User.fromJson)
        .toList();
  }

  Future<PointsBalance> adminFetchUserBalance(String userId) async {
    final response = await _auth.authenticatedRequest(
      'GET',
      ApiConstants.adminUserPoints(userId),
    );
    _throwIfFailed(response);
    return PointsBalance.fromJson(_decodeMap(response));
  }

  Future<List<PointsLedgerEntry>> adminFetchUserLedger(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(ApiConstants.adminUserLedger(userId)).replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final response = await _auth.authenticatedRequest('GET', uri.toString());
    _throwIfFailed(response);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PointsLedgerEntry.fromJson)
          .toList();
    }
    return const <PointsLedgerEntry>[];
  }

  Future<PointsBalance> adminCreditUser(
    String userId,
    int points, {
    String? memo,
  }) async {
    final response = await _auth.authenticatedRequest(
      'POST',
      ApiConstants.adminUserCredit(userId),
      body: {
        'points': points,
        if (memo != null && memo.trim().isNotEmpty) 'memo': memo.trim(),
      },
    );
    _throwIfFailed(response);
    return PointsBalance.fromJson(_decodeMap(response));
  }

  Future<PointsBalance> adminDebitUser(
    String userId,
    int points, {
    String? memo,
  }) async {
    final response = await _auth.authenticatedRequest(
      'POST',
      ApiConstants.adminUserDebit(userId),
      body: {
        'points': points,
        if (memo != null && memo.trim().isNotEmpty) 'memo': memo.trim(),
      },
    );
    _throwIfFailed(response);
    return PointsBalance.fromJson(_decodeMap(response));
  }

  Future<IssueCodesResult> adminIssueCodes({
    required int count,
    required int pointsEach,
    String? batchLabel,
    String? memo,
  }) async {
    final response = await _auth.authenticatedRequest(
      'POST',
      ApiConstants.adminIssueCodes,
      body: {
        'count': count,
        'points_each': pointsEach,
        if (batchLabel != null && batchLabel.trim().isNotEmpty)
          'batch_label': batchLabel.trim(),
        if (memo != null && memo.trim().isNotEmpty) 'memo': memo.trim(),
      },
    );
    _throwIfFailed(response);
    return IssueCodesResult.fromJson(_decodeMap(response));
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final decoded = jsonDecode(_bodyText(response));
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('响应格式错误');
  }

  List<dynamic> _extractList(Object? data, {required List<String> keys}) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in keys) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    return const [];
  }

  /// 统一按 UTF-8 解码原始字节：响应缺少 JSON content-type 时（例如被网关
  /// 改写的错误页），http 包会按 latin1 解码 `body`，中文文案会变成乱码。
  String _bodyText(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      return response.body;
    }
  }

  void _throwIfFailed(http.Response response) {
    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) return;
    final body = _bodyText(response);
    // 只有解析 JSON 本身可以失败回退；服务端给出的错误文案必须原样抛出，
    // 不能被同一个 catch 吞掉变成笼统的“请求失败”。
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map) {
      final serverMessage = decoded['message'] ?? decoded['error'];
      if (serverMessage != null && serverMessage.toString().trim().isNotEmpty) {
        throw Exception(serverMessage.toString());
      }
    }
    throw Exception('请求失败 ($statusCode)');
  }
}

class _DefaultAuthServiceProvider {
  const _DefaultAuthServiceProvider();
}
