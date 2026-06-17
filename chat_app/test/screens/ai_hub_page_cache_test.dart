import 'package:chat_app/models/chat.dart';
import 'package:chat_app/screens/ai/ai_hub_page.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('switching AI Hub sections does not reload service data',
      (tester) async {
    final botService = _CountingBotService();
    final chatService = _CountingChatDataService();

    await tester.pumpWidget(
      MaterialApp(
        home: AiHubPage(
          botService: botService,
          chatDataService: chatService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(botService.getMyBotsCalls, 1);
    expect(chatService.getChatRoomsCalls, 1);

    await tester.tap(find.textContaining('接入群聊'));
    await tester.pumpAndSettle();

    expect(botService.getMyBotsCalls, 1);
    expect(chatService.getChatRoomsCalls, 1);

    await tester.tap(find.textContaining('积分生成图片'));
    await tester.pumpAndSettle();

    expect(botService.getMyBotsCalls, 1);
    expect(chatService.getChatRoomsCalls, 1);
  });

  testWidgets('configuring a room bot stays in AI Hub and does not open chat',
      (tester) async {
    final botService = _CountingBotService(
      bots: [
        BotConfig(id: 7, botName: 'Room Bot', llmProvider: 'HERMES'),
      ],
    );
    final chatService = _CountingChatDataService();
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        home: AiHubPage(
          initialSection: 'rooms',
          botService: botService,
          chatDataService: chatService,
        ),
        routes: {
          '/chat/room-1': (_) => const Scaffold(body: Text('Chat route')),
        },
        navigatorObservers: [observer],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('配置 Bot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Room Bot').last);
    await tester.pumpAndSettle();

    expect(botService.addedRoomIds, [1]);
    expect(botService.addedBotIds, [7]);
    expect(find.text('Room Bot 已加入 测试会话'), findsOneWidget);
    expect(find.text('Chat route'), findsNothing);
    expect(observer.pushedRouteNames.where((name) => name.startsWith('/chat')),
        isEmpty);
  });
}

class _CountingBotService extends BotService {
  _CountingBotService({this.bots = const []});

  final List<BotConfig> bots;
  int getMyBotsCalls = 0;
  final List<int> addedRoomIds = [];
  final List<int> addedBotIds = [];

  @override
  Future<List<BotConfig>> getMyBots() async {
    getMyBotsCalls += 1;
    return bots;
  }

  @override
  Future<bool> addBotToRoom(
    int roomId,
    int botId, {
    String? triggerMode,
    String? keywords,
    String? roomNickname,
    String? roomPromptSuffix,
    bool? enabledInRoom,
  }) async {
    addedRoomIds.add(roomId);
    addedBotIds.add(botId);
    return true;
  }
}

class _CountingChatDataService extends ChatDataService {
  int getChatRoomsCalls = 0;

  @override
  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
  }) async {
    getChatRoomsCalls += 1;
    return [
      Chat(
        id: '1',
        name: '测试会话',
        type: ChatType.group,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final pushedRouteNames = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) {
      pushedRouteNames.add(name);
    }
    super.didPush(route, previousRoute);
  }
}
