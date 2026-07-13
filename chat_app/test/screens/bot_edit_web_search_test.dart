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
  String? savedImageApiKey;
  String? savedImageBaseUrl;

  @override
  Future<List<ProviderCredential>> getProviderCredentials(
          {String? provider}) async =>
      const [];

  @override
  Future<BotConfig> updateBot(
    int botId,
    BotConfig config, {
    String? apiKey,
    String? imageApiKey,
    String? imageBaseUrl,
  }) async {
    savedConfig = config;
    savedImageApiKey = imageApiKey;
    savedImageBaseUrl = imageBaseUrl;
    return config;
  }

  @override
  Future<BotConfig?> createBot(
    BotConfig config, {
    String? apiKey,
    String? imageApiKey,
    String? imageBaseUrl,
  }) async {
    savedConfig = config;
    savedImageApiKey = imageApiKey;
    savedImageBaseUrl = imageBaseUrl;
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
    expect(service.savedConfig!.enabledTools.toSet(), {
      'code_interpreter',
      'file_search',
      'web_search',
      'inspect_room_image'
    });
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
        {'code_interpreter', 'file_search', 'inspect_room_image'});
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
        {'lookup_my_points_balance', 'generate_image', 'inspect_room_image'});
  });

  testWidgets('vision switches persist and control inspect_room_image',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 12,
      botName: 'vision-bot',
      llmProvider: 'OPENAI',
      enabledTools: const ['inspect_room_image'],
    );
    await pumpEditor(tester, bot, service);

    final visionSwitch = find.byKey(const Key('bot-edit-vision-input-switch'));
    await tester.ensureVisible(visionSwitch);
    await tester.tap(visionSwitch);
    await tester.pumpAndSettle();

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig!.visionInputEnabled, isFalse);
    expect(service.savedConfig!.historyImageInspectionEnabled, isFalse);
    expect(service.savedConfig!.enabledTools,
        isNot(contains('inspect_room_image')));
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

  testWidgets('custom NovelAI image provider saves encrypted-key inputs',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 10,
      botName: 'novel-draw-bot',
      llmProvider: 'HERMES',
      enabledTools: const ['generate_image'],
    );
    await pumpEditor(tester, bot, service);

    await tester.ensureVisible(find.text('NovelAI'));
    await tester.tap(find.text('NovelAI'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '图片 API Key'),
      'novel-secret',
    );

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig!.imageGenerationProvider, 'NOVELAI');
    expect(service.savedConfig!.imageModel, 'nai-diffusion-3');
    expect(service.savedImageApiKey, 'novel-secret');
    expect(
      service.savedImageBaseUrl,
      'https://image.novelai.net/ai/generate-image',
    );
  });

  testWidgets('Kimi Code provider selects the kimi-code default model',
      (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 9,
      botName: 'kimi-bot',
      llmProvider: 'OPENAI',
    );
    await pumpEditor(tester, bot, service);

    await tester.ensureVisible(find.text('Kimi Code'));
    await tester.tap(find.text('Kimi Code'));
    await tester.pumpAndSettle();

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig, isNotNull);
    expect(service.savedConfig!.llmProvider, 'KIMI');
    expect(service.savedConfig!.modelName, 'kimi-code');
  });

  testWidgets('saving chunked reply mode sends replyMode', (tester) async {
    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 8,
      botName: 'talky-bot',
      llmProvider: 'HERMES',
      replyMode: 'SINGLE',
      replyIntervalSeconds: 3.5,
    );
    await pumpEditor(tester, bot, service);

    final chunkedChip = find.byKey(const Key('bot-reply-mode-chunked'));
    await tester.ensureVisible(chunkedChip);
    await tester.tap(chunkedChip);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bot-reply-interval-slider')), findsOneWidget);
    expect(find.text('3.5 秒'), findsOneWidget);

    final saveButton = find.text('保存 Bot').last;
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(service.savedConfig, isNotNull);
    expect(service.savedConfig!.replyMode, 'CHUNKED');
    expect(service.savedConfig!.replyIntervalSeconds, 3.5);
  });

  testWidgets('focusing system prompt preserves desktop page scroll position',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _CapturingBotService();
    final bot = BotConfig(
      id: 18,
      botName: 'scroll-bot',
      llmProvider: 'OPENAI',
      systemPrompt: List.filled(20, '保持当前位置').join('\n'),
    );
    await tester.pumpWidget(MaterialApp(
      home: BotEditScreen(bot: bot, botService: service),
    ));
    await tester.pumpAndSettle();

    final prompt = find.byKey(const Key('bot-system-prompt-field'));
    await tester.ensureVisible(prompt);
    await tester.pumpAndSettle();
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final before = scrollable.position.pixels;

    await tester.tap(prompt);
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, closeTo(before, 1));
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
