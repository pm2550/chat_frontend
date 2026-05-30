import 'dart:async';
import 'dart:convert';

import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/widgets/auth_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().clearLocalSession();
  });

  testWidgets('loading auth state keeps splash instead of navigating to login',
      (tester) async {
    final completer = Completer<bool>();

    await tester.pumpWidget(MaterialApp(
      routes: {
        '/login': (_) => const Text('login route'),
      },
      home: AuthGuard(
        authCheck: () => completer.future,
        child: const Text('protected content'),
      ),
    ));

    await tester.pump();

    expect(find.text('login route'), findsNothing);
    expect(find.text('protected content'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(true);
    await tester.pumpAndSettle();

    expect(find.text('protected content'), findsOneWidget);
    expect(find.text('login route'), findsNothing);
  });

  test('initialize restores cached session before network validation',
      () async {
    final userData = jsonEncode({
      'id': 9,
      'username': 'cached',
      'email': 'cached@example.com',
      'displayName': 'Cached User',
      'createdAt': '2026-05-28T00:00:00Z',
    });
    SharedPreferences.setMockInitialValues({
      'access_token': 'cached-access',
      'refresh_token': 'cached-refresh',
      'user_data': userData,
    });

    final service = AuthService();
    final authenticated = await service.initialize(validateInBackground: false);

    expect(authenticated, isTrue);
    expect(service.isAuthenticated, isTrue);
    expect(service.accessToken, 'cached-access');
    expect(service.currentUser?.username, 'cached');
  });

  test('initialize tolerates double encoded web user data', () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'cached-access',
      'refresh_token': 'cached-refresh',
      'user_data': jsonEncode(jsonEncode({
        'id': 10,
        'username': 'web-cached',
        'email': 'web-cached@example.com',
        'displayName': 'Web Cached User',
        'createdAt': '2026-05-28T00:00:00Z',
      })),
    });

    final service = AuthService();
    final authenticated = await service.initialize(validateInBackground: false);

    expect(authenticated, isTrue);
    expect(service.currentUser?.username, 'web-cached');
  });
}
