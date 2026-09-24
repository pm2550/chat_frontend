import 'package:chat_app/screens/settings/bot_webhook_section.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWebhookBotService extends BotService {
  _FakeWebhookBotService(this.webhooks) : super();

  List<BotWebhook> webhooks;
  final registered = <Map<String, Object?>>[];
  final deleted = <int>[];

  @override
  Future<List<BotWebhook>> listWebhooks(int botId) async => webhooks;

  @override
  Future<void> registerWebhook(
    int botId, {
    required String callbackUrl,
    String? secret,
    String? eventTypes,
    int? chatRoomId,
  }) async {
    registered.add({
      'callbackUrl': callbackUrl,
      'secret': secret,
      'eventTypes': eventTypes,
    });
    webhooks = [
      BotWebhook(id: 1, callbackUrl: callbackUrl, hasSecret: true),
    ];
  }

  @override
  Future<void> deleteWebhook(int subscriptionId) async {
    deleted.add(subscriptionId);
    webhooks = webhooks.where((w) => w.id != subscriptionId).toList();
  }
}

void main() {
  Future<void> pump(WidgetTester tester, _FakeWebhookBotService service) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BotWebhookSection(botService: service, botId: 7),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('existing webhook is listed and prefilled for update',
      (tester) async {
    final service = _FakeWebhookBotService([
      const BotWebhook(
        id: 1,
        callbackUrl: 'https://example.com/old',
        hasSecret: true,
        lastDeliveryStatus: 200,
      ),
    ]);
    await pump(tester, service);

    expect(find.text('https://example.com/old'), findsNWidgets(2));
    expect(find.text('更新 webhook'), findsOneWidget);
    expect(find.text('留空则沿用原来的 secret'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('bot-webhook-url')), 'https://example.com/new');
    await tester.tap(find.byKey(const Key('bot-webhook-save')));
    await tester.pumpAndSettle();

    expect(service.registered.single['callbackUrl'], 'https://example.com/new');
    expect(service.registered.single['eventTypes'], 'message');
    expect(find.byKey(const ValueKey('bot-webhook-1')), findsOneWidget);
    expect(find.textContaining('https://example.com/old'), findsNothing);
  });

  testWidgets('webhook can be deleted', (tester) async {
    final service = _FakeWebhookBotService([
      const BotWebhook(id: 3, callbackUrl: 'https://example.com/hook'),
    ]);
    await pump(tester, service);

    await tester.tap(find.byTooltip('删除 Webhook'));
    await tester.pumpAndSettle();

    expect(service.deleted, [3]);
    expect(find.text('尚未配置 Webhook'), findsOneWidget);
    expect(find.text('保存 webhook'), findsOneWidget);
  });
}
