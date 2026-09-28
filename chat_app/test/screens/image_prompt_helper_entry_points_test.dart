import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/ai/ai_hub_page.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/image_prompt_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_screen_test.dart'
    show FakeBotService, FakeChatDataService, buildTestWidget;

/// 三个画图入口（/画图、更多工具 → AI 图片、AI 中心画图）都能选扩写档位，并按选的发。
void main() {
  setUp(() {
    ChatScreen.clearMessageCacheForTesting();
    ImagePromptHelperPreference.resetForTesting();
  });

  Chat groupChat() {
    final now = DateTime.parse('2024-01-01T10:00:00');
    return Chat(
      id: '42',
      name: 'Draw Room',
      type: ChatType.group,
      createdAt: now,
      participants: [
        User(
          id: '2',
          username: 'alice',
          email: 'alice@test.com',
          displayName: 'Alice',
          createdAt: now,
        ),
      ],
    );
  }

  final composerShell =
      find.byKey(const ValueKey('chat-composer-text-field-shell'));
  final composerField =
      find.descendant(of: composerShell, matching: find.byType(TextField));
  final drawHint = find.byKey(const ValueKey('slash-draw-hint'));

  Future<_RecordingChatService> pumpChat(WidgetTester tester) async {
    final service = _RecordingChatService();
    await tester.pumpWidget(buildTestWidget(
      groupChat(),
      chatService: service,
      botService: FakeBotService(roomBots: const []),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(composerField);
    return service;
  }

  testWidgets('/画图 sends the default 创意扩写 level', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = await pumpChat(tester);

    await tester.enterText(composerField, '/画图 一只橘猫');
    await tester.pump();
    expect(find.text('扩写：创意扩写'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(service.requests, [('一只橘猫', ImagePromptHelper.medium)]);
  });

  testWidgets('/画图 hint lets you pick the level and sends it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = await pumpChat(tester);

    await tester.enterText(composerField, '/画图 一只橘猫');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('image-prompt-helper-compact')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('image-prompt-helper-menu-off')));
    await tester.pumpAndSettle();
    expect(find.text('扩写：关闭'), findsOneWidget);

    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(service.requests, [('一只橘猫', ImagePromptHelper.off)]);
    expect(drawHint, findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ImagePromptHelperPreference.prefsKey), 'off');
  });

  testWidgets('/画图 uses the level remembered on this device',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {ImagePromptHelperPreference.prefsKey: 'low'});
    final service = await pumpChat(tester);

    await tester.enterText(composerField, '/画图 一只橘猫');
    await tester.pumpAndSettle();
    expect(find.text('扩写：仅翻译'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(service.requests, [('一只橘猫', ImagePromptHelper.low)]);
  });

  testWidgets('/画图 hint with the level button fits a 320px phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await pumpChat(tester);

    await tester.enterText(composerField, '/画图 一只橘猫');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(drawHint, findsOneWidget);
    final button =
        find.byKey(const ValueKey('image-prompt-helper-compact'));
    expect(button, findsOneWidget);
    expect(tester.getRect(button).right, lessThanOrEqualTo(320));
    expect(find.textContaining('每天免费 3 次'), findsOneWidget);
  });

  testWidgets('AI 图片 sheet shows the free quota and sends the chosen level',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = await pumpChat(tester);

    await tester.tap(find.byTooltip('更多工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 图片'));
    await tester.pumpAndSettle();

    // 每天有免费次数：不能说"本次 10 积分"。
    expect(find.textContaining('本次 10 积分'), findsNothing);
    expect(find.text('每天免费 3 次，之后每次 10 积分。生成完成后会作为图片消息发到当前会话。'),
        findsOneWidget);
    expect(find.text('自动补充细节和画面感（默认）'), findsOneWidget);

    await tester.tap(find.text('仅翻译'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '描述你想生成的图片'), '雨后的街道');
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    expect(service.requests, [('雨后的街道', ImagePromptHelper.low)]);
  });

  testWidgets('AI Hub drawing tab replaces 快出图 with the level selector',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final chatService = _HubChatService();
    await tester.pumpWidget(MaterialApp(
      home: AiHubPage(
        botService: _EmptyBotService(),
        chatDataService: chatService,
        initialSection: 'images',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('快出图'), findsNothing);
    expect(find.text('创意扩写'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField,
            '描述你想要的图片，例如：一只蓝色玻璃杯放在雨后窗边，柔和自然光'),
        '蓝色玻璃杯');
    final off = find.byKey(const ValueKey('image-prompt-helper-off'));
    await tester.ensureVisible(off);
    await tester.pumpAndSettle();
    await tester.tap(off);
    await tester.pumpAndSettle();
    expect(find.text('按你写的原文出图'), findsOneWidget);
    await tester.ensureVisible(find.text('生成并发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成并发送'));
    // 提交后有出图进度动画，不能等 settle。
    await tester.pump();
    await tester.pump();

    expect(chatService.requests, [('1', '蓝色玻璃杯', ImagePromptHelper.off)]);
    // 停掉出图进度轮询的定时器。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Message _queuedImage(String chatRoomId, String prompt) => Message(
      id: 'image-gen-1',
      content: prompt,
      senderId: 'user1',
      senderName: '我',
      chatRoomId: chatRoomId,
      type: MessageType.imageGeneration,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      imageGenPrompt: prompt,
      imageGenStatus: 'QUEUED',
    );

class _RecordingChatService extends FakeChatDataService {
  _RecordingChatService() : super(messages: const []);

  final List<(String, ImagePromptHelper?)> requests = [];

  @override
  Future<Message> generateImageMessage(
    String chatRoomId, {
    required String prompt,
    String size = '1024*1024',
    bool expand = true,
    ImagePromptHelper? promptHelper,
  }) async {
    requests.add((prompt, promptHelper));
    return _queuedImage(chatRoomId, prompt);
  }
}

class _EmptyBotService extends BotService {
  @override
  Future<List<BotConfig>> getMyBots() async => const [];
}

class _HubChatService extends ChatDataService {
  final List<(String, String, ImagePromptHelper?)> requests = [];

  @override
  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
    ChatType? excludeType,
    bool forceRefresh = false,
  }) async {
    return [
      Chat(
        id: '1',
        name: '测试会话',
        type: ChatType.group,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<Message> generateImageMessage(
    String chatRoomId, {
    required String prompt,
    String size = '1024*1024',
    bool expand = true,
    ImagePromptHelper? promptHelper,
  }) async {
    requests.add((chatRoomId, prompt, promptHelper));
    return _queuedImage(chatRoomId, prompt);
  }

  @override
  Future<List<Message>> getRecentMessages(
    String chatRoomId, {
    int limit = 20,
  }) async =>
      const [];
}
