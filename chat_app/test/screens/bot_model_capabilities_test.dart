import 'package:chat_app/screens/ai/bot_model_capabilities.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('temperature support mirrors the backend LLMService rules', () {
    expect(botSupportsTemperature('OPENAI', 'gpt-4.1'), isTrue);
    expect(botSupportsTemperature('OPENAI', 'gpt-5-mini'), isFalse);
    expect(botSupportsTemperature('OPENAI', 'o3'), isFalse);
    expect(botSupportsTemperature('CLAUDE', 'claude-3-5-sonnet'), isTrue);
    expect(
        botSupportsTemperature('CLAUDE', 'claude-sonnet-4-20250514'), isTrue);
    expect(botSupportsTemperature('CLAUDE', 'claude-opus-4-6'), isTrue);
    expect(botSupportsTemperature('CLAUDE', 'claude-opus-4-7'), isFalse);
    expect(botSupportsTemperature('CLAUDE', 'claude-sonnet-5'), isFalse);
    expect(botSupportsTemperature('OLLAMA', 'kimi-k2.6'), isTrue);
    expect(botSupportsTemperature('HERMES', 'grok-4.3'), isTrue);
  });

  test('blank model falls back to the server default model', () {
    expect(effectiveBotModel('CLAUDE', ''), 'claude-sonnet-4-20250514');
    expect(effectiveBotModel('OLLAMA', '  ', modelOverride: 'Kimi-K2.6'),
        'kimi-k2.6');
    expect(
        botSupportsReasoningEffort('OLLAMA', effectiveBotModel('OLLAMA', '')),
        isFalse);
  });

  test('BotConfig omits workflowMode it never received', () {
    final bot =
        BotConfig.fromJson({'id': 1, 'botName': 'x', 'llmProvider': 'OPENAI'});
    expect(bot.workflowMode, isNull);
    expect(bot.toJson().containsKey('workflowMode'), isFalse);

    final kirara = BotConfig.fromJson({
      'id': 2,
      'botName': 'y',
      'llmProvider': 'OPENAI',
      'workflowMode': 'KIRARA_TWO_PASS'
    });
    expect(kirara.toJson()['workflowMode'], 'KIRARA_TWO_PASS');
  });
}
