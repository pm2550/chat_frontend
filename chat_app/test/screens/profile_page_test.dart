import 'dart:convert';

import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/profile_page.dart';
import 'package:chat_app/screens/profile/profile_edit_screen.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  Widget buildProfilePage(FakeUserProfileService service) {
    return MaterialApp(
      routes: {
        '/login': (_) => const Scaffold(body: Text('Login Page')),
      },
      home: ProfilePage(profileService: service),
    );
  }

  group('ProfilePage', () {
    testWidgets('renders current user profile from service', (tester) async {
      final service = FakeUserProfileService(
        profile: testUser(
          '1',
          'Alice',
          email: 'alice@example.com',
          phone: '123',
          bio: 'Product builder',
          status: OnlineStatus.online,
        ),
      );

      await tester.pumpWidget(buildProfilePage(service));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('alice@example.com'), findsWidgets);
      expect(find.text('Product builder'), findsWidgets);
      expect(find.text('在线状态'), findsOneWidget);
    });

    testWidgets('updates online status from the status chips', (tester) async {
      final service = FakeUserProfileService(
        profile: testUser('1', 'Alice', status: OnlineStatus.online),
      );

      await tester.pumpWidget(buildProfilePage(service));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChoiceChip).at(1));
      await tester.pumpAndSettle();

      expect(service.statusUpdates, [OnlineStatus.away]);
      expect(find.text('状态已更新为 离开'), findsOneWidget);
    });
  });

  group('ProfileEditScreen', () {
    testWidgets('saves edited profile through profile service', (tester) async {
      final service = FakeUserProfileService(
        profile: testUser('1', 'Alice', email: 'alice@example.com'),
      );

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          user: service.profile,
          profileService: service,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '显示名称'),
        'Alice New',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '头衔'),
        '值班',
      );
      await tester.tap(find.byTooltip('保存'));
      await tester.pumpAndSettle();

      expect(service.updateRequests.single.displayName, 'Alice New');
      expect(service.titleUpdates.single.title, '值班');
    });

    testWidgets('picks and uploads avatar with fake picker', (tester) async {
      final service = FakeUserProfileService(
        profile: testUser('1', 'Alice', email: 'alice@example.com'),
      );

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          user: service.profile,
          profileService: service,
          avatarPicker: () async => PickedProfileAvatar(
            name: 'avatar.png',
            size: transparentPngBytes.length,
            bytes: transparentPngBytes,
            mimeType: 'image/png',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('选择头像'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();

      expect(service.uploadedAvatars.single.name, 'avatar.png');
      expect(find.text('头像上传成功'), findsOneWidget);
    });
  });
}

final transparentPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);

class FakeUserProfileService extends UserProfileService {
  FakeUserProfileService({required this.profile})
      : super(authenticatedRequest: _unusedRequest);

  User profile;
  final List<UserProfileUpdateRequest> updateRequests = [];
  final List<TitleUpdate> titleUpdates = [];
  final List<PickedProfileAvatar> uploadedAvatars = [];
  final List<OnlineStatus> statusUpdates = [];

  static Future<http.Response> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> updateTitle({
    String? title,
    String? titleColor,
    String titleEffect = 'none',
  }) async {
    titleUpdates.add(TitleUpdate(title, titleColor, titleEffect));
    profile = profile.copyWith(
      title: title,
      titleColor: titleColor,
      titleEffect: titleEffect,
    );
    return profile;
  }

  @override
  Future<User> getProfile() async => profile;

  @override
  Future<User> updateProfile(UserProfileUpdateRequest request) async {
    updateRequests.add(request);
    profile = profile.copyWith(
      displayName: request.displayName,
      email: request.email,
      phone: request.phone,
      bio: request.bio,
      onlineStatus: request.onlineStatus == null
          ? profile.onlineStatus
          : OnlineStatus.values.firstWhere(
              (status) =>
                  status.name.toUpperCase() ==
                  request.onlineStatus!.toUpperCase(),
              orElse: () => profile.onlineStatus,
            ),
    );
    return profile;
  }

  @override
  Future<String> uploadAvatar(PickedProfileAvatar avatar) async {
    uploadedAvatars.add(avatar);
    const avatarUrl = '/api/files/avatar/new.png';
    profile = profile.copyWith(avatarUrl: avatarUrl);
    return avatarUrl;
  }

  @override
  Future<void> deleteAvatar() async {}

  @override
  Future<OnlineStatus> updateOnlineStatus(OnlineStatus status) async {
    statusUpdates.add(status);
    profile = profile.copyWith(onlineStatus: status);
    return status;
  }
}

class TitleUpdate {
  const TitleUpdate(this.title, this.titleColor, this.titleEffect);

  final String? title;
  final String? titleColor;
  final String titleEffect;
}

User testUser(
  String id,
  String displayName, {
  String email = 'alice@example.com',
  String? phone,
  String? bio,
  OnlineStatus status = OnlineStatus.offline,
}) {
  return User(
    id: id,
    username: displayName.toLowerCase(),
    email: email,
    phone: phone,
    displayName: displayName,
    bio: bio,
    onlineStatus: status,
    createdAt: DateTime.parse('2024-01-01T10:00:00'),
  );
}
