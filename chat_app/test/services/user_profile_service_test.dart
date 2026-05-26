import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    authService = AuthService();
    await authService.replaceCurrentUser(testUser('1', 'Alice'));
  });

  group('UserProfileService', () {
    test('getProfile reads backend profile response and updates auth cache',
        () async {
      final calls = <String>[];
      final service = UserProfileService(
        authService: authService,
        authenticatedRequest: (
          method,
          url, {
          headers,
          body,
        }) async {
          calls.add('$method $url');
          return jsonResponse({
            'success': true,
            'data': userJson('1', 'Alice Real',
                avatarUrl: '/api/files/avatar/a.png'),
          });
        },
      );

      final user = await service.getProfile();

      expect(calls, ['GET ${ApiConstants.profile}']);
      expect(user.displayName, 'Alice Real');
      expect(authService.currentUser?.avatarUrl, '/api/files/avatar/a.png');
    });

    test('updateProfile sends profile body and parses returned user', () async {
      Object? sentBody;
      final service = UserProfileService(
        authService: authService,
        authenticatedRequest: (
          method,
          url, {
          headers,
          body,
        }) async {
          expect(method, 'PUT');
          expect(url, ApiConstants.profile);
          sentBody = body;
          return jsonResponse({
            'success': true,
            'data': userJson('1', 'Alice Updated', email: 'new@example.com'),
          });
        },
      );

      final user = await service.updateProfile(UserProfileUpdateRequest(
        displayName: 'Alice Updated',
        email: 'new@example.com',
        onlineStatus: 'BUSY',
      ));

      expect(sentBody, {
        'displayName': 'Alice Updated',
        'email': 'new@example.com',
        'onlineStatus': 'BUSY',
      });
      expect(user.email, 'new@example.com');
      expect(authService.currentUser?.displayName, 'Alice Updated');
    });

    test('uploadAvatar uses multipart avatar field and updates cached avatar',
        () async {
      PickedProfileAvatar? uploaded;
      final service = UserProfileService(
        authService: authService,
        multipartRequest: (url, {required avatar}) async {
          expect(url, ApiConstants.profileAvatar);
          uploaded = avatar;
          return jsonResponse({
            'success': true,
            'data': {'avatarUrl': '/api/files/avatar/new.png'},
          });
        },
      );

      final avatarUrl = await service.uploadAvatar(const PickedProfileAvatar(
        name: 'avatar.png',
        size: 4,
        mimeType: 'image/png',
        bytes: [1, 2, 3, 4],
      ));

      expect(uploaded?.name, 'avatar.png');
      expect(avatarUrl, '/api/files/avatar/new.png');
      expect(authService.currentUser?.avatarUrl, '/api/files/avatar/new.png');
    });

    test('deleteAvatar calls backend and clears cached avatar', () async {
      await authService.replaceCurrentUser(
        testUser('1', 'Alice', avatarUrl: '/api/files/avatar/old.png'),
      );
      final calls = <String>[];
      final service = UserProfileService(
        authService: authService,
        authenticatedRequest: (
          method,
          url, {
          headers,
          body,
        }) async {
          calls.add('$method $url');
          return jsonResponse({'success': true});
        },
      );

      await service.deleteAvatar();

      expect(calls, ['DELETE ${ApiConstants.profileAvatar}']);
      expect(authService.currentUser?.avatarUrl, isNull);
    });

    test('updateOnlineStatus calls status endpoint and updates cached user',
        () async {
      final service = UserProfileService(
        authService: authService,
        authenticatedRequest: (
          method,
          url, {
          headers,
          body,
        }) async {
          expect(method, 'PUT');
          expect(url, ApiConstants.profileStatus('AWAY'));
          return jsonResponse({
            'success': true,
            'data': {'onlineStatus': 'AWAY'},
          });
        },
      );

      final status = await service.updateOnlineStatus(OnlineStatus.away);

      expect(status, OnlineStatus.away);
      expect(authService.currentUser?.onlineStatus, OnlineStatus.away);
    });
  });
}

http.Response jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> userJson(
  String id,
  String displayName, {
  String email = 'alice@example.com',
  String? avatarUrl,
}) {
  return {
    'id': id,
    'username': displayName.toLowerCase().replaceAll(' ', '_'),
    'email': email,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'onlineStatus': 'ONLINE',
    'createdAt': '2024-01-01T10:00:00',
  };
}

User testUser(String id, String displayName, {String? avatarUrl}) {
  return User(
    id: id,
    username: displayName.toLowerCase(),
    email: '${displayName.toLowerCase()}@example.com',
    displayName: displayName,
    avatarUrl: avatarUrl,
    createdAt: DateTime.parse('2024-01-01T10:00:00'),
  );
}
