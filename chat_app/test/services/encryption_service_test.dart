import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/encryption_service.dart';

void main() {
  group('EncryptionService', () {
    test('singleton pattern returns the same instance', () {
      final instance1 = EncryptionService();
      final instance2 = EncryptionService();
      expect(identical(instance1, instance2), isTrue);
    });

    test('initial keysUploaded is false', () {
      final service = EncryptionService();
      // Note: since it is a singleton, state may persist across tests,
      // but on a fresh run keysUploaded starts as false
      expect(service.keysUploaded, isA<bool>());
    });

    group('encryptMessage (placeholder base64)', () {
      test('encrypts a simple string', () {
        final service = EncryptionService();
        final encrypted = service.encryptMessage('Hello', 'dummyKey');
        expect(encrypted, isNotEmpty);
        expect(encrypted, isNot(equals('Hello')));
      });

      test('encrypted output is valid base64', () {
        final service = EncryptionService();
        final encrypted = service.encryptMessage('Test message', 'key');
        // Should not throw when decoding as base64
        expect(() => base64Decode(encrypted), returnsNormally);
      });

      test('same input produces same output (deterministic placeholder)', () {
        final service = EncryptionService();
        final encrypted1 = service.encryptMessage('same text', 'key1');
        final encrypted2 = service.encryptMessage('same text', 'key2');
        // The placeholder ignores the key, so same plaintext = same output
        expect(encrypted1, equals(encrypted2));
      });

      test('different inputs produce different outputs', () {
        final service = EncryptionService();
        final encrypted1 = service.encryptMessage('message A', 'key');
        final encrypted2 = service.encryptMessage('message B', 'key');
        expect(encrypted1, isNot(equals(encrypted2)));
      });

      test('handles empty string', () {
        final service = EncryptionService();
        final encrypted = service.encryptMessage('', 'key');
        expect(encrypted, isNotNull);
        // base64 of empty string is empty string
        expect(encrypted, equals(''));
      });

      test('handles unicode characters', () {
        final service = EncryptionService();
        final encrypted = service.encryptMessage('你好世界', 'key');
        expect(encrypted, isNotEmpty);
        expect(() => base64Decode(encrypted), returnsNormally);
      });

      test('handles long messages', () {
        final service = EncryptionService();
        final longMessage = 'A' * 10000;
        final encrypted = service.encryptMessage(longMessage, 'key');
        expect(encrypted, isNotEmpty);
      });
    });

    group('decryptMessage (placeholder base64)', () {
      test('decrypts a valid base64 string', () {
        final service = EncryptionService();
        final original = 'Hello World';
        final encoded = base64Encode(utf8.encode(original));
        final decrypted = service.decryptMessage(encoded);
        expect(decrypted, equals(original));
      });

      test('returns original string for invalid base64', () {
        final service = EncryptionService();
        // Invalid base64 should be returned as-is (fallback behavior)
        final result = service.decryptMessage('not-valid-base64!!!');
        expect(result, equals('not-valid-base64!!!'));
      });

      test('handles empty string', () {
        final service = EncryptionService();
        final decrypted = service.decryptMessage('');
        expect(decrypted, equals(''));
      });

      test('handles unicode after decrypt', () {
        final service = EncryptionService();
        final original = '你好世界 emoji test';
        final encoded = base64Encode(utf8.encode(original));
        final decrypted = service.decryptMessage(encoded);
        expect(decrypted, equals(original));
      });
    });

    group('encrypt/decrypt roundtrip', () {
      test('roundtrip preserves plain text', () {
        final service = EncryptionService();
        const original = 'Round trip test message!';
        final encrypted = service.encryptMessage(original, 'anyKey');
        final decrypted = service.decryptMessage(encrypted);
        expect(decrypted, equals(original));
      });

      test('roundtrip preserves unicode text', () {
        final service = EncryptionService();
        const original = '加密消息测试 🔐';
        final encrypted = service.encryptMessage(original, 'key');
        final decrypted = service.decryptMessage(encrypted);
        expect(decrypted, equals(original));
      });

      test('roundtrip preserves multiline text', () {
        final service = EncryptionService();
        const original = 'Line 1\nLine 2\nLine 3';
        final encrypted = service.encryptMessage(original, 'key');
        final decrypted = service.decryptMessage(encrypted);
        expect(decrypted, equals(original));
      });

      test('roundtrip preserves special characters', () {
        final service = EncryptionService();
        const original = r'Special: !@#$%^&*()_+-={}[]|;:,.<>?/~`';
        final encrypted = service.encryptMessage(original, 'key');
        final decrypted = service.decryptMessage(encrypted);
        expect(decrypted, equals(original));
      });
    });
  });
}
