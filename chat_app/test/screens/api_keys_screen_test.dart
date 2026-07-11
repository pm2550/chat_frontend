import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chat_app/screens/ai/api_keys_screen.dart';
import 'package:chat_app/services/bot_service.dart';

class _FakeBotService extends BotService {
  _FakeBotService(this._credentials) : super();

  final List<ProviderCredential> _credentials;
  ProviderCredential? created;
  int? deletedId;
  int? updatedId;

  @override
  Future<List<ProviderCredential>> getProviderCredentials(
      {String? provider}) async {
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

  @override
  Future<ProviderCredential> updateProviderCredential({
    required int credentialId,
    String? label,
    String? secret,
    bool? isActive,
    String? memo,
    String? baseUrl,
    String? modelOverride,
  }) async {
    updatedId = credentialId;
    return ProviderCredential(
      id: credentialId,
      llmProvider: 'OPENAI',
      label: label ?? '',
      baseUrl: baseUrl,
      modelOverride: modelOverride,
    );
  }
}

void main() {
  testWidgets('shows empty state when there are no credentials',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApiKeysScreen(botService: _FakeBotService(const [])),
    ));
    await tester.pumpAndSettle();

    expect(find.text('还没有密钥'), findsOneWidget);
    expect(find.text('添加密钥'), findsOneWidget);
  });

  testWidgets('reveals the add form with provider chips on tap',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ApiKeysScreen(botService: _FakeBotService(const [])),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加密钥'));
    await tester.pumpAndSettle();

    expect(find.text('保存密钥'), findsOneWidget);
    expect(find.text('DASHSCOPE'), findsOneWidget);
    expect(find.text('NOVELAI'), findsOneWidget);
    expect(find.text('IMAGE_API'), findsOneWidget);
    expect(find.text('OPENAI'), findsWidgets);
  });

  testWidgets('lists existing credentials with provider and base_url',
      (tester) async {
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
    await tester
        .pumpWidget(MaterialApp(home: ApiKeysScreen(botService: service)));
    await tester.pumpAndSettle();

    expect(find.text('my-openrouter'), findsOneWidget);
    expect(find.textContaining('openrouter.ai'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation before calling the service',
      (tester) async {
    final service = _FakeBotService(const [
      ProviderCredential(
          id: 5, llmProvider: 'OPENAI', label: 'my-key', secretLast4: 'abcd'),
    ]);
    await tester
        .pumpWidget(MaterialApp(home: ApiKeysScreen(botService: service)));
    await tester.pumpAndSettle();

    // Tapping delete opens a confirm dialog — it must NOT delete immediately.
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除密钥'), findsOneWidget);
    expect(service.deletedId, isNull, reason: 'must not delete before confirm');

    // Cancelling leaves the credential intact.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.deletedId, isNull);

    // Confirming actually deletes.
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('删除')));
    await tester.pumpAndSettle();
    expect(service.deletedId, 5);
  });

  testWidgets('edit pre-fills the form and calls update, not create',
      (tester) async {
    final service = _FakeBotService(const [
      ProviderCredential(
        id: 8,
        llmProvider: 'OPENAI',
        label: 'editme',
        secretLast4: 'wxyz',
        baseUrl: 'https://api.example.com/v1',
      ),
    ]);
    await tester
        .pumpWidget(MaterialApp(home: ApiKeysScreen(botService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();

    // Form opens in edit mode (save button reads '保存修改') pre-filled with the label.
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('editme'), findsWidgets);

    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(service.updatedId, 8);
    expect(service.created, isNull,
        reason: 'editing must update, never create a new credential');
  });
}
