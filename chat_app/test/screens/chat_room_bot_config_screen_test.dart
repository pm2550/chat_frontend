import 'package:chat_app/screens/chat/chat_room_bot_config_screen.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBotService extends BotService {
  int updateCalls = 0;

  @override
  Future<BotConfig> updateRoomBotConfig(
    int roomId,
    int botId, {
    String? triggerMode,
    String? keywords,
    String? roomNickname,
    String? roomPromptSuffix,
    bool? enabledInRoom,
  }) async {
    updateCalls++;
    return BotConfig(id: botId, botName: 'Helper', llmProvider: 'OPENAI');
  }
}

class FakeChatDataService extends ChatDataService {
  int? lastModerationGrantBotId;
  String? lastModerationGrant;

  @override
  Future<void> setChatRoomBotModerationGrant({
    required String chatRoomId,
    required int botId,
    required String grant,
  }) async {
    lastModerationGrantBotId = botId;
    lastModerationGrant = grant;
  }
}

Future<void> openScreen(
  WidgetTester tester, {
  required bool isOwner,
  required FakeBotService bot,
  required FakeChatDataService chat,
  String grant = 'NONE',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatRoomBotConfigScreen(
                    roomId: 42,
                    bot: BotConfig(
                      id: 7,
                      botName: 'Helper',
                      llmProvider: 'OPENAI',
                      moderationGrant: grant,
                    ),
                    botService: bot,
                    chatService: chat,
                    isOwner: isOwner,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('ChatRoomBotConfigScreen moderation grant', () {
    testWidgets('nonOwnerSeesModerationChipsAsDisabled', (tester) async {
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final bot = FakeBotService();
      final chat = FakeChatDataService();
      await openScreen(tester, isOwner: false, bot: bot, chat: chat);

      expect(find.text('管理权限 (群主可设)'), findsOneWidget);
      expect(find.text('仅群主可修改。'), findsOneWidget);

      // Chips are non-interactive (onTap null) and saving must NOT push a grant.
      await tester.tap(find.text('可移出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();

      expect(chat.lastModerationGrant, isNull);
    });

    testWidgets('ownerCanChangeModerationGrantAndSaveCallsBackend',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final bot = FakeBotService();
      final chat = FakeChatDataService();
      await openScreen(tester, isOwner: true, bot: bot, chat: chat);

      await tester.tap(find.text('可移出')); // KICK
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();

      expect(bot.updateCalls, 1);
      expect(chat.lastModerationGrantBotId, 7);
      expect(chat.lastModerationGrant, 'KICK');
    });
  });
}
