import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/chat_history_service.dart';

void main() {
  group('ChatHistoryService', () {
    test('can be instantiated without auth token', () {
      final service = ChatHistoryService();
      expect(service, isA<ChatHistoryService>());
    });

    test('can be instantiated with auth token', () {
      final service = ChatHistoryService(authToken: 'test-token-123');
      expect(service, isA<ChatHistoryService>());
    });

    test('authToken is null when not provided', () {
      final service = ChatHistoryService();
      expect(service.authToken, isNull);
    });

    test('authToken is stored when provided', () {
      const token = 'my-secret-token';
      final service = ChatHistoryService(authToken: token);
      expect(service.authToken, equals(token));
    });

    test('multiple instances are independent', () {
      final service1 = ChatHistoryService(authToken: 'token-1');
      final service2 = ChatHistoryService(authToken: 'token-2');
      expect(identical(service1, service2), isFalse);
      expect(service1.authToken, isNot(equals(service2.authToken)));
    });

    test('instance with empty string token is different from null token', () {
      final serviceNull = ChatHistoryService();
      final serviceEmpty = ChatHistoryService(authToken: '');
      expect(serviceNull.authToken, isNull);
      expect(serviceEmpty.authToken, equals(''));
    });
  });
}
