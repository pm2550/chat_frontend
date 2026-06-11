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
}

class _CountingBotService extends BotService {
  int getMyBotsCalls = 0;

  @override
  Future<List<BotConfig>> getMyBots() async {
    getMyBotsCalls += 1;
    return const [];
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
        id: 'room-1',
        name: '测试会话',
        type: ChatType.group,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }
}
