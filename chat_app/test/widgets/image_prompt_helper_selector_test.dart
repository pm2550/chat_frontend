import 'package:chat_app/services/image_prompt_helper.dart';
import 'package:chat_app/widgets/image_prompt_helper_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 画图扩写档位选择：默认创意扩写，选了记在本机，下次打开还是它。
void main() {
  setUp(ImagePromptHelperPreference.resetForTesting);

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );

  testWidgets('defaults to 创意扩写 and persists a new choice', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host(const ImagePromptHelperSelector()));
    await tester.pumpAndSettle();

    for (final label in ['关闭', '仅翻译', '创意扩写']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('自动补充细节和画面感（默认）'), findsOneWidget);
    expect(ImagePromptHelperPreference.current.value, ImagePromptHelper.medium);

    await tester.tap(find.text('仅翻译'));
    await tester.pumpAndSettle();

    expect(find.text('只把描述翻译给画图模型，不改写'), findsOneWidget);
    expect(ImagePromptHelperPreference.current.value, ImagePromptHelper.low);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ImagePromptHelperPreference.prefsKey), 'low');

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('按你写的原文出图'), findsOneWidget);
    expect(prefs.getString(ImagePromptHelperPreference.prefsKey), 'off');
  });

  testWidgets('restores the choice saved on this device', (tester) async {
    SharedPreferences.setMockInitialValues(
        {ImagePromptHelperPreference.prefsKey: 'off'});
    await tester.pumpWidget(host(const ImagePromptHelperSelector()));
    await tester.pumpAndSettle();

    expect(find.text('按你写的原文出图'), findsOneWidget);
    expect(await ImagePromptHelperPreference.load(), ImagePromptHelper.off);
  });

  testWidgets('an unknown saved value falls back to 创意扩写', (tester) async {
    SharedPreferences.setMockInitialValues(
        {ImagePromptHelperPreference.prefsKey: 'ultra'});
    await tester.pumpWidget(host(const ImagePromptHelperSelector()));
    await tester.pumpAndSettle();

    expect(ImagePromptHelperPreference.current.value, ImagePromptHelper.medium);
    expect(find.text('自动补充细节和画面感（默认）'), findsOneWidget);
  });

  testWidgets('compact button opens a menu and shares the same choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host(const Column(children: [
      ImagePromptHelperSelector(compact: true),
      SizedBox(height: 16),
      ImagePromptHelperSelector(),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('扩写：创意扩写'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-prompt-helper-compact')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('image-prompt-helper-menu-low')));
    await tester.pumpAndSettle();

    expect(find.text('扩写：仅翻译'), findsOneWidget);
    // 完整版也跟着变。
    expect(find.text('只把描述翻译给画图模型，不改写'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ImagePromptHelperPreference.prefsKey), 'low');
  });

  testWidgets('disabled selector ignores taps', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .pumpWidget(host(const ImagePromptHelperSelector(enabled: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(ImagePromptHelperPreference.current.value, ImagePromptHelper.medium);
  });

  testWidgets('full selector fits a 320px phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    // "AI 图片"面板里：外边距 16 + 卡片内边距 18。
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(34),
          child: ImagePromptHelperSelector(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('创意扩写'), findsOneWidget);
  });
}
