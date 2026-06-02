import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chat_app/screens/ai/api_keys_screen.dart';
import 'package:chat_app/services/bot_service.dart';

class _FakeBotService extends BotService {
  _FakeBotService(this._credentials) : super();

  final List<ProviderCredential> _credentials;
  ProviderCredential? created;
  int? deletedId;

  @override
  Future<List<ProviderCredential>> getProviderCredentials({String? provider}) async {
    return _credentials;
  }

  @override
  Future<ProviderCredential> createProviderCredential({
    required String provider,
    required String label,
    required String secret,
    String? memo,
    String? baseUrl,
    String? modelOverride,
  }) async {
    created = ProviderCredential(
      id: 99,
      llmProvider: provider,
      label: label,
      baseUrl: baseUrl,
      modelOverride: modelOverride,
    );
    return created!;
  }

  @override
  Future<void> deleteProviderCredential(int credentialId) async {
    deletedId = credentialId;
  }
}

void main() {
  testWidgets('shows empty state when there are no credentials', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApiKeysScreen(botService: _FakeBotService(const [])),
    ));
    await tester.pumpAndSettle();

    expect(find.text('还没有密钥'), findsOneWidget);
    expect(find.text('添加密钥'), findsOneWidget);
  });

  testWidgets('reveals the add form with provider chips on tap', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApiKeysScreen(botService: _FakeBotService(const [])),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加密钥'));
    await tester.pumpAndSettle();

    expect(find.text('保存密钥'), findsOneWidget);
    expect(find.text('DASHSCOPE'), findsOneWidget);
    expect(find.text('OPENAI'), findsWidgets);
  });

  testWidgets('lists existing credentials with provider and base_url', (tester) async {
    final service = _FakeBotService(const [
      ProviderCredential(
        id: 5,
        llmProvider: 'OPENAI',
        label: 'my-openrouter',
        secretLast4: 'abcd',
        baseUrl: 'https://openrouter.ai/api/v1',
        modelOverride: 'anthropic/claude',
      ),
    ]);
    await tester.pumpWidget(MaterialApp(home: ApiKeysScreen(botService: service)));
    await tester.pumpAndSettle();

    expect(find.text('my-openrouter'), findsOneWidget);
    expect(find.textContaining('openrouter.ai'), findsOneWidget);
  });
}
