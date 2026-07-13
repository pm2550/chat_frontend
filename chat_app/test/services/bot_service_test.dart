import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:http/http.dart' as http;

void main() {
  group('BotConfig', () {
    test('can be constructed with required fields', () {
      final config = BotConfig(
        botName: 'TestBot',
        llmProvider: 'OPENAI',
      );
      expect(config.botName, equals('TestBot'));
      expect(config.llmProvider, equals('OPENAI'));
    });

    test('has correct default values', () {
      final config = BotConfig(
        botName: 'TestBot',
        llmProvider: 'OPENAI',
      );
      expect(config.id, isNull);
      expect(config.botAvatar, isNull);
      expect(config.modelName, isNull);
      expect(config.systemPrompt, isNull);
      expect(config.temperature, equals(0.7));
      expect(config.maxTokens, equals(2048));
      expect(config.visionInputEnabled, isTrue);
      expect(config.historyImageInspectionEnabled, isTrue);
      expect(config.replyMode, equals('SINGLE'));
      expect(config.replyIntervalSeconds, equals(2.0));
      expect(config.isActive, isTrue);
    });

    test('can be constructed with all fields', () {
      final config = BotConfig(
        id: 1,
        botName: 'FullBot',
        botAvatar: 'https://example.com/avatar.png',
        llmProvider: 'ANTHROPIC',
        modelName: 'claude-3',
        systemPrompt: 'You are a helpful assistant.',
        temperature: 0.9,
        maxTokens: 4096,
        isActive: false,
      );
      expect(config.id, equals(1));
      expect(config.botName, equals('FullBot'));
      expect(config.botAvatar, equals('https://example.com/avatar.png'));
      expect(config.llmProvider, equals('ANTHROPIC'));
      expect(config.modelName, equals('claude-3'));
      expect(config.systemPrompt, equals('You are a helpful assistant.'));
      expect(config.temperature, equals(0.9));
      expect(config.maxTokens, equals(4096));
      expect(config.isActive, isFalse);
    });

    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'id': 42,
          'botName': 'JsonBot',
          'botAvatar': 'https://example.com/bot.png',
          'llmProvider': 'OPENAI',
          'modelName': 'gpt-4',
          'systemPrompt': 'Be helpful',
          'temperature': 0.5,
          'maxTokens': 1024,
          'replyMode': 'CHUNKED',
          'replyIntervalSeconds': 3.5,
          'visionInputEnabled': false,
          'historyImageInspectionEnabled': false,
          'isActive': true,
        };

        final config = BotConfig.fromJson(json);
        expect(config.id, equals(42));
        expect(config.botName, equals('JsonBot'));
        expect(config.botAvatar, equals('https://example.com/bot.png'));
        expect(config.llmProvider, equals('OPENAI'));
        expect(config.modelName, equals('gpt-4'));
        expect(config.systemPrompt, equals('Be helpful'));
        expect(config.temperature, equals(0.5));
        expect(config.maxTokens, equals(1024));
        expect(config.replyMode, equals('CHUNKED'));
        expect(config.replyIntervalSeconds, equals(3.5));
        expect(config.visionInputEnabled, isFalse);
        expect(config.historyImageInspectionEnabled, isFalse);
        expect(config.isActive, isTrue);
      });

      test('uses defaults for missing optional fields', () {
        final json = <String, dynamic>{};

        final config = BotConfig.fromJson(json);
        expect(config.id, isNull);
        expect(config.botName, equals(''));
        expect(config.botAvatar, isNull);
        expect(config.llmProvider, equals('OPENAI'));
        expect(config.modelName, isNull);
        expect(config.systemPrompt, isNull);
        expect(config.temperature, equals(0.7));
        expect(config.maxTokens, equals(2048));
        expect(config.isActive, isTrue);
        expect(config.visionInputEnabled, isTrue);
        expect(config.historyImageInspectionEnabled, isTrue);
      });

      test('handles integer temperature by converting to double', () {
        final json = {
          'botName': 'Bot',
          'llmProvider': 'OPENAI',
          'temperature': 1,
        };

        final config = BotConfig.fromJson(json);
        expect(config.temperature, isA<double>());
        expect(config.temperature, equals(1.0));
      });

      test('handles null values gracefully', () {
        final json = {
          'id': null,
          'botName': null,
          'botAvatar': null,
          'llmProvider': null,
          'modelName': null,
          'systemPrompt': null,
          'temperature': null,
          'maxTokens': null,
          'isActive': null,
        };

        final config = BotConfig.fromJson(json);
        expect(config.id, isNull);
        expect(config.botName, equals(''));
        expect(config.llmProvider, equals('OPENAI'));
        expect(config.temperature, equals(0.7));
        expect(config.maxTokens, equals(2048));
        expect(config.isActive, isTrue);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final config = BotConfig(
          botName: 'SerBot',
          botAvatar: 'avatar.png',
          llmProvider: 'ANTHROPIC',
          modelName: 'claude-3',
          systemPrompt: 'Be concise',
          temperature: 0.3,
          maxTokens: 512,
          replyMode: 'CHUNKED',
          replyIntervalSeconds: 4.0,
        );

        final json = config.toJson();
        expect(json['botName'], equals('SerBot'));
        expect(json['botAvatar'], equals('avatar.png'));
        expect(json['llmProvider'], equals('ANTHROPIC'));
        expect(json['modelName'], equals('claude-3'));
        expect(json['systemPrompt'], equals('Be concise'));
        expect(json['temperature'], equals(0.3));
        expect(json['maxTokens'], equals(512));
        expect(json['replyMode'], equals('CHUNKED'));
        expect(json['replyIntervalSeconds'], equals(4.0));
        expect(json['visionInputEnabled'], isTrue);
        expect(json['historyImageInspectionEnabled'], isTrue);
      });

      test('does not include id in toJson', () {
        final config = BotConfig(
          id: 99,
          botName: 'Bot',
          llmProvider: 'OPENAI',
        );

        final json = config.toJson();
        expect(json.containsKey('id'), isFalse);
      });

      test('does not include isActive in toJson', () {
        final config = BotConfig(
          botName: 'Bot',
          llmProvider: 'OPENAI',
          isActive: false,
        );

        final json = config.toJson();
        expect(json.containsKey('isActive'), isFalse);
      });

      test('includes null optional fields', () {
        final config = BotConfig(
          botName: 'MinBot',
          llmProvider: 'OPENAI',
        );

        final json = config.toJson();
        expect(json.containsKey('botAvatar'), isTrue);
        expect(json['botAvatar'], isNull);
        expect(json.containsKey('modelName'), isTrue);
        expect(json['modelName'], isNull);
        expect(json.containsKey('systemPrompt'), isTrue);
        expect(json['systemPrompt'], isNull);
      });
    });

    test('roundtrip fromJson -> toJson preserves data', () {
      final originalJson = {
        'id': 10,
        'botName': 'RoundBot',
        'botAvatar': 'round.png',
        'llmProvider': 'OPENAI',
        'modelName': 'gpt-4',
        'systemPrompt': 'Be round',
        'temperature': 0.8,
        'maxTokens': 2000,
        'isActive': true,
      };

      final config = BotConfig.fromJson(originalJson);
      final outputJson = config.toJson();

      // toJson does not include 'id' or 'isActive', verify the rest
      expect(outputJson['botName'], equals(originalJson['botName']));
      expect(outputJson['llmProvider'], equals(originalJson['llmProvider']));
      expect(outputJson['modelName'], equals(originalJson['modelName']));
      expect(outputJson['systemPrompt'], equals(originalJson['systemPrompt']));
      expect(outputJson['temperature'], equals(originalJson['temperature']));
      expect(outputJson['maxTokens'], equals(originalJson['maxTokens']));
    });
  });

  group('BotService', () {
    test('can be instantiated', () {
      final service = BotService();
      expect(service, isA<BotService>());
    });

    test('multiple instances are independent (not singleton)', () {
      final service1 = BotService();
      final service2 = BotService();
      expect(identical(service1, service2), isFalse);
    });

    test('getMyBots reads ApiResponse data list', () async {
      final service = BotService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(url, contains('/api/v1/bots/my'));
          return jsonResponse({
            'code': 200,
            'data': [
              {
                'id': 1,
                'botName': 'Helper',
                'llmProvider': 'OPENAI',
                'modelName': 'gpt-4o',
                'providerCredentialId': 8,
                'providerCredentialLabel': 'prod openai',
                'providerCredentialLast4': '1234',
                'hasCredential': true,
              },
            ],
          });
        },
      );

      final bots = await service.getMyBots();

      expect(bots, hasLength(1));
      expect(bots.first.botName, 'Helper');
      expect(bots.first.modelName, 'gpt-4o');
      expect(bots.first.providerCredentialId, 8);
      expect(bots.first.providerCredentialLabel, 'prod openai');
      expect(bots.first.providerCredentialLast4, '1234');
      expect(bots.first.hasCredential, isTrue);
    });

    test('createBot posts config and api key', () async {
      Object? capturedBody;
      final service = BotService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          capturedBody = body;
          return jsonResponse({
            'code': 200,
            'data': {
              'id': 2,
              'botName': 'NewBot',
              'llmProvider': 'OLLAMA',
            },
          });
        },
      );

      final bot = await service.createBot(
        BotConfig(botName: 'NewBot', llmProvider: 'OLLAMA'),
        apiKey: 'secret',
      );

      expect((capturedBody as Map<String, dynamic>)['apiKey'], 'secret');
      expect(bot?.id, 2);
      expect(bot?.botName, 'NewBot');
    });

    test('BotConfig toJson includes provider credential id without secret', () {
      final config = BotConfig(
        botName: 'VaultBot',
        llmProvider: 'OPENAI',
        providerCredentialId: 7,
        hasCredential: true,
      );

      final json = config.toJson();

      expect(json['providerCredentialId'], 7);
      expect(json.containsKey('apiKey'), isFalse);
    });

    test('provider credentials can be listed and created', () async {
      final calls = <String>[];
      Object? capturedBody;
      final service = BotService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method $url');
          if (method == 'POST') capturedBody = body;
          if (method == 'GET') {
            return jsonResponse({
              'code': 200,
              'data': [
                {
                  'id': 3,
                  'llmProvider': 'OPENAI',
                  'label': 'prod',
                  'secretLast4': 'abcd',
                  'isActive': true,
                }
              ],
            });
          }
          return jsonResponse({
            'code': 200,
            'data': {
              'id': 4,
              'llmProvider': 'OPENAI',
              'label': 'new',
              'secretLast4': '1234',
              'isActive': true,
            },
          });
        },
      );

      final listed = await service.getProviderCredentials(provider: 'OPENAI');
      final created = await service.createProviderCredential(
        provider: 'OPENAI',
        label: 'new',
        secret: 'sk-1234',
      );

      expect(
          calls[0], contains('/api/v1/provider-credentials?provider=OPENAI'));
      expect(listed.single.label, 'prod');
      expect(created.id, 4);
      expect((capturedBody as Map<String, dynamic>)['secret'], 'sk-1234');
    });

    test('room bot management calls backend endpoints', () async {
      final calls = <String>[];
      final service = BotService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method $url');
          return jsonResponse({'code': 200, 'data': null});
        },
      );

      await service.addBotToRoom(42, 5, triggerMode: 'MENTION');
      await service.removeBotFromRoom(42, 5);
      await service.deleteBot(5);

      expect(calls[0], contains('/api/v1/bots/chat-rooms/42/bots/5/add'));
      expect(calls[1], startsWith('DELETE '));
      expect(calls[1], contains('/api/v1/bots/chat-rooms/42/bots/5'));
      expect(calls[2], contains('/api/v1/bots/5'));
    });

    test('character card import posts card and parses summary', () async {
      Object? capturedBody;
      final service = BotService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          expect(url, contains('/api/v1/bots/7/character-card/import'));
          capturedBody = body;
          return jsonResponse({
            'code': 200,
            'data': {
              'id': 7,
              'botName': 'Kirara',
              'llmProvider': 'OPENAI',
              'hasCharacterCard': true,
              'characterPersona': 'A fox courier.',
              'characterFirstMes': 'Package delivered!',
              'characterAlternateGreetings': ['Hi!', 'Ready.'],
              'characterBookEntryCount': 2,
            },
          });
        },
      );

      final bot = await service.importCharacterCard(7, {
        'spec': 'chara_card_v2',
        'data': {'name': 'Kirara'},
      });

      expect((capturedBody as Map<String, dynamic>)['card'], isA<Map>());
      expect(bot.hasCharacterCard, isTrue);
      expect(bot.characterAlternateGreetings, ['Hi!', 'Ready.']);
      expect(bot.characterBookEntryCount, 2);
    });

    test('character card export returns card map', () async {
      final service = BotService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(url, contains('/api/v1/bots/7/character-card/export'));
          return jsonResponse({
            'code': 200,
            'data': {
              'spec': 'chara_card_v2',
              'data': {'name': 'Kirara'},
            },
          });
        },
      );

      final card = await service.exportCharacterCard(7);

      expect(card['spec'], 'chara_card_v2');
      expect(card['data'], isA<Map<String, dynamic>>());
    });

    test('failed response throws BotServiceException', () async {
      final service = BotService(
        authenticatedRequest: (method, url, {headers, body}) async {
          return jsonResponse({'message': '无权限'}, statusCode: 403);
        },
      );

      expect(
        () => service.getMyBots(),
        throwsA(isA<BotServiceException>()),
      );
    });
  });
}

http.Response jsonResponse(
  Object body, {
  int statusCode = 200,
}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
