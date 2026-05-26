import 'dart:convert';
import 'dart:developer' as developer;
import '../constants/api_constants.dart';
import 'auth_service.dart';

class AnonymousIdentity {
  final int? id;
  final String anonymousName;
  final String? anonymousAvatar;
  final bool customNameUsed;

  AnonymousIdentity({
    this.id,
    required this.anonymousName,
    this.anonymousAvatar,
    this.customNameUsed = false,
  });

  factory AnonymousIdentity.fromJson(Map<String, dynamic> json) {
    return AnonymousIdentity(
      id: json['id'],
      anonymousName: json['anonymousName'] ?? '匿名用户',
      anonymousAvatar: json['anonymousAvatar'],
      customNameUsed: json['customNameUsed'] ?? false,
    );
  }
}

class AnonymousService {
  final AuthService _authService = AuthService();

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
