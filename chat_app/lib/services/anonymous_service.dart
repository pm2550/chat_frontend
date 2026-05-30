import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'auth_service.dart';

enum ChatAnonymousMode { sticky, perMessage }

class AnonymousIdentity {
  final int? id;
  final String anonymousName;
  final String? anonymousAvatar;
  final bool customNameUsed;
  final AnonymousThemeInfo? theme;
  final int? dailyRemaining;
  final DateTime? quotaResetsAt;

  AnonymousIdentity({
    this.id,
    required this.anonymousName,
    this.anonymousAvatar,
    this.customNameUsed = false,
    this.theme,
    this.dailyRemaining,
    this.quotaResetsAt,
  });

  factory AnonymousIdentity.fromJson(Map<String, dynamic> json) {
    return AnonymousIdentity(
      id: json['id'],
      anonymousName: json['anonymousName'] ?? '匿名用户',
      anonymousAvatar: json['anonymousAvatar'],
      customNameUsed: json['customNameUsed'] ?? false,
      theme: json['theme'] is Map<String, dynamic>
          ? AnonymousThemeInfo.fromJson(json['theme'] as Map<String, dynamic>)
          : null,
      dailyRemaining: _intOrNull(json['dailyRemaining']),
      quotaResetsAt: _dateTimeOrNull(json['quotaResetsAt']),
    );
  }

  static int? _intOrNull(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _dateTimeOrNull(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

class AnonymousQuota {
  final int used;
  final int remaining;
  final DateTime? resetsAt;

  const AnonymousQuota({
    required this.used,
    required this.remaining,
    this.resetsAt,
  });

  factory AnonymousQuota.fromJson(Map<String, dynamic> json) {
    return AnonymousQuota(
      used: AnonymousIdentity._intOrNull(json['used']) ?? 0,
      remaining: AnonymousIdentity._intOrNull(json['remaining']) ?? 0,
      resetsAt: AnonymousIdentity._dateTimeOrNull(json['resetsAt']),
    );
  }
}

class RerollResult {
  final AnonymousIdentity? identity;
  final bool quotaExhausted;
  final String? message;
  final DateTime? resetsAt;

  const RerollResult._({
    this.identity,
    this.quotaExhausted = false,
    this.message,
    this.resetsAt,
  });

  factory RerollResult.success(AnonymousIdentity identity) =>
      RerollResult._(identity: identity);

  factory RerollResult.quotaExhausted({
    String? message,
    DateTime? resetsAt,
  }) =>
      RerollResult._(
        quotaExhausted: true,
        message: message,
        resetsAt: resetsAt,
      );

  factory RerollResult.failed([String? message]) =>
      RerollResult._(message: message);

  bool get isSuccess => identity != null;
}

class AnonymousThemeInfo {
  final int? id;
  final String themeKey;
  final String displayName;
  final String? description;
  final String? accentColor;
  final String? backgroundColor;
  final String? messageColor;
  final String? personaPrefix;

  const AnonymousThemeInfo({
    this.id,
    required this.themeKey,
    required this.displayName,
    this.description,
    this.accentColor,
    this.backgroundColor,
    this.messageColor,
    this.personaPrefix,
  });

  factory AnonymousThemeInfo.fromJson(Map<String, dynamic> json) {
    return AnonymousThemeInfo(
      id: json['id'],
      themeKey: json['themeKey']?.toString() ?? 'default',
      displayName: json['displayName']?.toString() ?? '经典匿名',
      description: json['description']?.toString(),
      accentColor: json['accentColor']?.toString(),
      backgroundColor: json['backgroundColor']?.toString(),
      messageColor: json['messageColor']?.toString(),
      personaPrefix: json['personaPrefix']?.toString(),
    );
  }
}

class AnonymousService {
  final AuthService _authService = AuthService();

  Future<ChatAnonymousMode> getMode(int roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_modeKey(roomId));
    return value == ChatAnonymousMode.perMessage.name
        ? ChatAnonymousMode.perMessage
        : ChatAnonymousMode.sticky;
  }

  Future<void> setMode(int roomId, ChatAnonymousMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey(roomId), mode.name);
  }

  String _modeKey(int roomId) {
    final userId = _authService.currentUser?.id ?? 'guest';
    return 'anonymous_mode:$userId:$roomId';
  }

  Future<AnonymousIdentity?> enterAnonymousMode(int roomId) async {
    try {
      final response = await _authService.authenticatedRequest(
        'POST',
        ApiConstants.enterAnonymous(roomId),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] != null) {
        return AnonymousIdentity.fromJson(data['data']);
      }
    } catch (e) {
      developer.log('Enter anonymous mode error', error: e);
    }
    return null;
  }

  Future<AnonymousIdentity?> renameAnonymous(int roomId, String newName) async {
    try {
      final response = await _authService.authenticatedRequest(
        'PUT',
        ApiConstants.renameAnonymous(roomId),
        body: {'newName': newName},
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] != null) {
        return AnonymousIdentity.fromJson(data['data']);
      }
    } catch (e) {
      developer.log('Rename anonymous error', error: e);
    }
    return null;
  }

  Future<AnonymousIdentity?> rerollAnonymous(int roomId) async {
    final result = await rerollAnonymousWithResult(roomId);
    return result.identity;
  }

  Future<RerollResult> rerollAnonymousWithResult(int roomId) async {
    try {
      final response = await _authService.authenticatedRequest(
        'POST',
        ApiConstants.rerollAnonymous(roomId),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] != null) {
        return RerollResult.success(AnonymousIdentity.fromJson(data['data']));
      }
      if (response.statusCode == 429) {
        return RerollResult.quotaExhausted(
          message: data is Map<String, dynamic>
              ? data['message']?.toString()
              : '今日匿名身份切换次数已用完，请明天再试',
        );
      }
    } catch (e) {
      developer.log('Reroll anonymous error', error: e);
    }
    return RerollResult.failed('匿名身份重抽失败');
  }

  Future<AnonymousQuota?> getQuota() async {
    try {
      final response = await _authService.authenticatedRequest(
        'GET',
        ApiConstants.anonymousQuota,
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] is Map<String, dynamic>) {
        return AnonymousQuota.fromJson(data['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      developer.log('Get anonymous quota error', error: e);
    }
    return null;
  }

  Future<List<AnonymousThemeInfo>> listThemes(int roomId) async {
    try {
      final response = await _authService.authenticatedRequest(
        'GET',
        ApiConstants.anonymousThemes(roomId),
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final value = data['data'];
      if (response.statusCode == 200 && value is List) {
        return value
            .whereType<Map<String, dynamic>>()
            .map(AnonymousThemeInfo.fromJson)
            .toList();
      }
    } catch (e) {
      developer.log('List anonymous themes error', error: e);
    }
    return const [];
  }

  Future<AnonymousThemeInfo?> updateTheme(int roomId, String themeKey) async {
    try {
      final response = await _authService.authenticatedRequest(
        'PUT',
        ApiConstants.anonymousTheme(roomId),
        body: {'themeKey': themeKey},
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] is Map<String, dynamic>) {
        return AnonymousThemeInfo.fromJson(
            data['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      developer.log('Update anonymous theme error', error: e);
    }
    return null;
  }

  Future<bool> toggleAnonymous(int roomId, bool enable) async {
    try {
      final response = await _authService.authenticatedRequest(
        'PUT',
        '${ApiConstants.toggleAnonymous(roomId)}?enable=$enable',
      );
      return response.statusCode == 200;
    } catch (e) {
      developer.log('Toggle anonymous error', error: e);
      return false;
    }
  }
}
