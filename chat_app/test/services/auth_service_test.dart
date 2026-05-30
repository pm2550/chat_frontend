import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:http/http.dart' as http;

void main() {
  group('AuthService', () {
    test('singleton pattern returns the same instance', () {
      final instance1 = AuthService();
      final instance2 = AuthService();
      expect(identical(instance1, instance2), isTrue);
    });

    test('is a ChangeNotifier', () {
      final service = AuthService();
      expect(service, isA<ChangeNotifier>());
    });

    test('initial state has no current user', () {
      final service = AuthService();
      expect(service.currentUser, isNull);
    });

    test('initial state has no access token', () {
      final service = AuthService();
      expect(service.accessToken, isNull);
    });

    test('initial state has no refresh token', () {
      final service = AuthService();
      expect(service.refreshToken, isNull);
    });

    test('initial state is not loading', () {
      final service = AuthService();
      expect(service.isLoading, isFalse);
    });

    test('isAuthenticated returns false when no token', () {
      final service = AuthService();
      // With no token set, isAuthenticated should be false
      expect(service.isAuthenticated, isFalse);
    });

    test(
        'isAuthenticated returns false when no user even if token concept exists',
        () {
      final service = AuthService();
      // Both token AND user must be non-null for isAuthenticated
      // Since neither is set on a fresh singleton, this confirms the logic
      expect(service.accessToken, isNull);
      expect(service.currentUser, isNull);
      expect(service.isAuthenticated, isFalse);
    });

    test('isAuthenticated requires both token and user to be non-null', () {
      final service = AuthService();
      // Verify the contract: isAuthenticated == (token != null && user != null)
      final expected =
          service.accessToken != null && service.currentUser != null;
      expect(service.isAuthenticated, equals(expected));
    });

    test('can add and remove listeners as ChangeNotifier', () {
      final service = AuthService();
      int callCount = 0;
      void listener() {
        callCount++;
      }

      service.addListener(listener);
      // We cannot easily trigger notifyListeners without calling a method
      // that makes HTTP calls, but we can verify add/remove doesn't throw
      service.removeListener(listener);
      expect(callCount, equals(0));
    });

    test('multiple factory calls share state', () {
      final service1 = AuthService();
      final service2 = AuthService();
      // Since they are the same instance, state should be shared
      expect(service1.accessToken, equals(service2.accessToken));
      expect(service1.currentUser, equals(service2.currentUser));
      expect(service1.isAuthenticated, equals(service2.isAuthenticated));
      expect(service1.isLoading, equals(service2.isLoading));
    });

    test('plain forbidden is not treated as an authentication failure', () {
      final service = AuthService();

      expect(
        service.debugIsAuthenticationFailure(http.Response('Forbidden', 403)),
        isFalse,
      );
      expect(
        service.debugIsAuthenticationFailure(http.Response(
          '{"message":"JWT token expired"}',
          403,
        )),
        isTrue,
      );
    });
  });
}
