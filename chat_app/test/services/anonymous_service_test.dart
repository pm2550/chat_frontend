import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/anonymous_service.dart';

void main() {
  group('AnonymousIdentity', () {
    test('can be constructed with required fields', () {
      final identity = AnonymousIdentity(anonymousName: 'Ghost123');
      expect(identity.anonymousName, equals('Ghost123'));
    });

    test('has correct default values', () {
      final identity = AnonymousIdentity(anonymousName: 'Anon');
      expect(identity.id, isNull);
      expect(identity.anonymousAvatar, isNull);
      expect(identity.customNameUsed, isFalse);
    });

    test('can be constructed with all fields', () {
      final identity = AnonymousIdentity(
        id: 5,
        anonymousName: 'Shadow',
        anonymousAvatar: 'https://example.com/anon.png',
        customNameUsed: true,
      );
      expect(identity.id, equals(5));
      expect(identity.anonymousName, equals('Shadow'));
      expect(identity.anonymousAvatar, equals('https://example.com/anon.png'));
      expect(identity.customNameUsed, isTrue);
    });

    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'id': 10,
          'anonymousName': 'Phantom',
          'anonymousAvatar': 'phantom.png',
          'customNameUsed': true,
        };

        final identity = AnonymousIdentity.fromJson(json);
        expect(identity.id, equals(10));
        expect(identity.anonymousName, equals('Phantom'));
        expect(identity.anonymousAvatar, equals('phantom.png'));
        expect(identity.customNameUsed, isTrue);
      });

      test('uses default anonymous name when missing', () {
        final json = <String, dynamic>{};

        final identity = AnonymousIdentity.fromJson(json);
        // Default is '匿名用户' (anonymous user in Chinese)
        expect(identity.anonymousName, equals('匿名用户'));
      });

      test('uses default customNameUsed false when missing', () {
        final json = {
          'anonymousName': 'TestUser',
        };

        final identity = AnonymousIdentity.fromJson(json);
        expect(identity.customNameUsed, isFalse);
      });

      test('handles null values gracefully', () {
        final json = {
          'id': null,
          'anonymousName': null,
          'anonymousAvatar': null,
          'customNameUsed': null,
        };

        final identity = AnonymousIdentity.fromJson(json);
        expect(identity.id, isNull);
        expect(identity.anonymousName, equals('匿名用户'));
        expect(identity.anonymousAvatar, isNull);
        expect(identity.customNameUsed, isFalse);
      });

      test('handles integer id correctly', () {
        final json = {
          'id': 999,
          'anonymousName': 'User999',
        };

        final identity = AnonymousIdentity.fromJson(json);
        expect(identity.id, equals(999));
      });
    });
  });

  group('AnonymousService', () {
    test('can be instantiated', () {
      final service = AnonymousService();
      expect(service, isA<AnonymousService>());
    });

    test('multiple instances are independent (not singleton)', () {
      final service1 = AnonymousService();
      final service2 = AnonymousService();
      expect(identical(service1, service2), isFalse);
    });
  });
}
