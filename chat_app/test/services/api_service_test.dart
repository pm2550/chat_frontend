import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/api_service.dart';
import 'package:chat_app/constants/api_constants.dart';

void main() {
  group('ApiService', () {
    late ApiService apiService;

    setUp(() {
      apiService = ApiService();
    });

    test('can be instantiated', () {
      expect(apiService, isA<ApiService>());
    });

    test('multiple instances are independent (not singleton)', () {
      final service1 = ApiService();
      final service2 = ApiService();
      expect(identical(service1, service2), isFalse);
    });

    test('timeoutDuration is 30 seconds', () {
      expect(ApiService.timeoutDuration, equals(const Duration(seconds: 30)));
    });

    test('setAuthToken and clearAuthToken do not throw', () {
      expect(() => apiService.setAuthToken('test-token'), returnsNormally);
      expect(() => apiService.clearAuthToken(), returnsNormally);
    });

    test('clearAuthToken can be called without setting token first', () {
      expect(() => apiService.clearAuthToken(), returnsNormally);
    });
  });

  group('ApiConstants', () {
    test('baseUrl is configured', () {
      expect(ApiConstants.baseUrl, isNotEmpty);
      expect(ApiConstants.baseUrl, contains('://'));
    });

    test('apiBaseUrl includes base URL and prefix and version', () {
      expect(ApiConstants.apiBaseUrl, startsWith(ApiConstants.baseUrl));
      expect(ApiConstants.apiBaseUrl, contains(ApiConstants.apiPrefix));
      expect(ApiConstants.apiBaseUrl, contains(ApiConstants.apiVersion));
    });

    test('auth endpoints start with authBaseUrl', () {
      expect(ApiConstants.login, startsWith(ApiConstants.authBaseUrl));
      expect(ApiConstants.register, startsWith(ApiConstants.authBaseUrl));
      expect(ApiConstants.logout, startsWith(ApiConstants.authBaseUrl));
      expect(ApiConstants.refreshToken, startsWith(ApiConstants.authBaseUrl));
      expect(ApiConstants.validateToken, startsWith(ApiConstants.authBaseUrl));
    });

    test('wsEndpoint uses ws protocol', () {
      expect(ApiConstants.wsEndpoint, startsWith('ws://'));
    });

    test('chat room dynamic endpoints include room ID', () {
      expect(ApiConstants.chatRoomDetail(42), contains('42'));
      expect(ApiConstants.chatRoomMembers(42), contains('42'));
      expect(ApiConstants.joinChatRoom(42), contains('42'));
      expect(ApiConstants.leaveChatRoom(42), contains('42'));
    });

    test('message dynamic endpoints include IDs', () {
      expect(ApiConstants.chatRoomMessages(10), contains('10'));
      expect(ApiConstants.markMessageRead(5), contains('5'));
      expect(ApiConstants.recallMessage(7), contains('7'));
      expect(ApiConstants.deleteMessage(3), contains('3'));
    });

    test('user dynamic endpoints include user ID', () {
      expect(ApiConstants.getUserById(99), contains('99'));
      expect(ApiConstants.uploadAvatar(99), contains('99'));
    });

    test('bot dynamic endpoints include IDs', () {
      expect(ApiConstants.botDetail(1), contains('1'));
      expect(ApiConstants.addBotToRoom(10, 5), contains('10'));
      expect(ApiConstants.addBotToRoom(10, 5), contains('5'));
      expect(ApiConstants.removeBotFromRoom(10, 5), contains('10'));
      expect(ApiConstants.removeBotFromRoom(10, 5), contains('5'));
      expect(ApiConstants.botsInRoom(10), contains('10'));
    });

    test('anonymous dynamic endpoints include room ID', () {
      expect(ApiConstants.enterAnonymous(8), contains('8'));
      expect(ApiConstants.renameAnonymous(8), contains('8'));
      expect(ApiConstants.toggleAnonymous(8), contains('8'));
    });

    test('key exchange dynamic endpoints include user ID', () {
      expect(ApiConstants.getKeyBundle(15), contains('15'));
      expect(ApiConstants.keyExists(15), contains('15'));
    });

    test('requestTimeout is 30 seconds', () {
      expect(ApiConstants.requestTimeout, equals(const Duration(seconds: 30)));
    });

    test('uploadTimeout is 120 seconds', () {
      expect(ApiConstants.uploadTimeout, equals(const Duration(seconds: 120)));
    });
  });
}
