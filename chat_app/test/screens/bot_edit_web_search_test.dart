import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chat_app/screens/ai/bot_edit_screen.dart';
import 'package:chat_app/services/bot_service.dart';

/// Captures the BotConfig handed to create/update so we can assert how the
/// web_search toggle composes enabled_tools (it must be a set-union with the
/// bot's existing tools — flipping web_search may not clobber the others).
class _CapturingBotService extends BotService {
  _CapturingBotService() : super();

  BotConfig? savedConfig;

  @override
  Future<List<ProviderCredential>> getProviderCredentials(
          {String? provider}) async =>
      const [];

  @override
  Future<BotConfig> updateBot(int botId, BotConfig config,
      {String? apiKey}) async {
    savedConfig = config;
    return config;
  }

  @override
  Future<BotConfig?> createBot(BotConfig config, {String? apiKey}) async {
    savedConfig = config;
    return config;
  }
}

void main() {
  Future<void> pumpEditor(
      WidgetTester tester, BotConfig bot, _CapturingBotService service) async {
    // Tall, narrow surface so the whole form fits without scrolling — otherwise the
    // Switch / save button land off-screen and taps miss (hit-test warning).
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: BotEditScreen(bot: bot, botService: service),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('toggling web_search ON preserves the bot\'s other tools (union)',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 3,
      botName: 'tools-bot',
      llmProvider: 'OPENAI',
      enabledTools: const ['code_interpreter', 'file_search'],
    );
    await pumpEditor(tester, bot, service);

    // web_search starts OFF; flip it ON.
    final webSearchSwitch = find.byKey(const Key('bot-edit-web-search-switch'));
    await tester.ensureVisible(webSearchSwitch);
    await tester.tap(webSearchSwitch);
    await tester.pumpAndSettle();

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig, isNotNull);
    expect(service.savedConfig!.enabledTools.toSet(),
        {'code_interpreter', 'file_search', 'web_search'});
  });

  testWidgets('toggling web_search OFF removes only web_search',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 4,
      botName: 'tools-bot',
      llmProvider: 'OPENAI',
      enabledTools: const ['code_interpreter', 'file_search', 'web_search'],
    );
    await pumpEditor(tester, bot, service);

    // web_search starts ON; flip it OFF.
    final webSearchSwitch = find.byKey(const Key('bot-edit-web-search-switch'));
    await tester.ensureVisible(webSearchSwitch);
    await tester.tap(webSearchSwitch);
    await tester.pumpAndSettle();

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig!.enabledTools.toSet(),
        {'code_interpreter', 'file_search'});
  });

  testWidgets('toggling image generation ON preserves other tools',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 5,
      botName: 'draw-bot',
      llmProvider: 'HERMES',
      enabledTools: const ['lookup_my_points_balance'],
    );
    await pumpEditor(tester, bot, service);

    await tester.ensureVisible(
        find.byKey(const Key('bot-edit-image-generation-switch')));
    await tester.tap(find.byKey(const Key('bot-edit-image-generation-switch')));
    await tester.pumpAndSettle();

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig!.enabledTools.toSet(),
        {'lookup_my_points_balance', 'generate_image'});
  });

  testWidgets('image bot preset selects Hermes Grok and enables draw tool',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 6,
      botName: 'preset-bot',
      llmProvider: 'OPENAI',
      enabledTools: const [],
    );
    await pumpEditor(tester, bot, service);

    await tester.ensureVisible(find.text('设为画图 Bot'));
    await tester.tap(find.text('设为画图 Bot'));
    await tester.pumpAndSettle();

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig!.llmProvider, 'HERMES');
    expect(service.savedConfig!.modelName, 'grok-4.3');
    expect(service.savedConfig!.enabledTools, contains('generate_image'));
    expect(service.savedConfig!.systemPrompt, contains('generate_image'));
  });

  testWidgets('saving allowlist policy sends allowed user tokens',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 7,
      botName: 'private-draw-bot',
      llmProvider: 'HERMES',
      accessPolicy: 'PRIVATE',
      enabledTools: const ['generate_image'],
    );
    await pumpEditor(tester, bot, service);

    final allowlistChip = find.byKey(const Key('bot-access-allowlist'));
    await tester.ensureVisible(allowlistChip);
    await tester.tap(allowlistChip);
    await tester.pumpAndSettle();

    final allowedUsersField =
        find.byKey(const Key('bot-access-allowed-users-field'));
    await tester.enterText(allowedUsersField, 'alice, 42');
    await tester.pumpAndSettle();

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig, isNotNull);
    expect(service.savedConfig!.accessPolicy, 'ALLOWLIST');
    expect(service.savedConfig!.allowedUsernames, ['alice', '42']);
  });
}
