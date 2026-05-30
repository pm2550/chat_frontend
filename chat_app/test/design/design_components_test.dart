import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/chat_customization.dart';
import 'package:chat_app/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  User user() => User(
        id: '1',
        username: 'alex',
        email: 'alex@pmchat.local',
        displayName: 'Alex Chen',
        onlineStatus: OnlineStatus.online,
        createdAt: DateTime(2026),
      );

  Widget harness(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  testWidgets('PMListRow renders title subtitle and badge', (tester) async {
    await tester.pumpWidget(
      harness(
        PMListRow(
          leading: PMUserAvatar(user: user(), showOnlineDot: true),
          title: const Text('Alex Chen'),
          subtitle: const Text('Workspace owner'),
          badge: '3',
        ),
      ),
    );

    expect(find.text('Alex Chen'), findsOneWidget);
    expect(find.text('Workspace owner'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('PMButton calls onPressed once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      harness(PMButton(label: '保存', onPressed: () => taps++)),
    );

    await tester.tap(find.text('保存'));
    expect(taps, 1);
  });

  testWidgets('PMAttachmentCard renders file metadata and progress',
      (tester) async {
    await tester.pumpWidget(
      harness(
        const SizedBox(
          width: 320,
          child: PMAttachmentCard(
            type: AttachmentType.file,
            name: 'proposal.pdf',
            sizeText: '2.4 MB',
            progress: 0.5,
          ),
        ),
      ),
    );

    expect(find.text('proposal.pdf'), findsOneWidget);
    expect(find.text('2.4 MB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('PMEmptyState and PMErrorState expose actions', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      harness(
        PMErrorState(
          message: 'Forbidden',
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('Forbidden'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('PMSymbolIcon and PMChip leading render without icon font',
      (tester) async {
    await tester.pumpWidget(
      harness(
        const PMChip(
          label: '成员',
          selected: true,
          leading: PMSymbolIcon(PMSymbol.members),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('成员'), findsOneWidget);
  });

  testWidgets('PMSymbolIcon paints every PM symbol without Material glyphs',
      (tester) async {
    await tester.pumpWidget(
      harness(
        Wrap(
          children: [
            for (final symbol in PMSymbol.values)
              PMSymbolIcon(symbol, key: ValueKey(symbol), size: 24),
          ],
        ),
      ),
    );

    for (final symbol in PMSymbol.values) {
      expect(find.byKey(ValueKey(symbol)), findsOneWidget);
    }
  });

  testWidgets('chat customization previews render with custom painters',
      (tester) async {
    await tester.pumpWidget(
      harness(
        const SizedBox(
          width: 360,
          height: 220,
          child: Column(
            children: [
              Expanded(child: PMBackgroundPreview(preset: 'aurora')),
              SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: Row(
                  children: [
                    Expanded(
                      child: PMAvatarFramePreview(preset: 'cyber_glow'),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: PMBubbleStylePreview(preset: 'retro_block'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('PM'), findsOneWidget);
  });

  testWidgets('solid chat background preset renders without painter',
      (tester) async {
    expect(ChatCustomizationCatalog.isValidBackground('solid:#EAF4FF'), isTrue);
    expect(
        ChatCustomizationCatalog.isValidBackground('solid:#XYZ123'), isFalse);

    await tester.pumpWidget(
      harness(
        const SizedBox(
          width: 180,
          height: 120,
          child: PMBackgroundPreview(preset: 'solid:#EAF4FF'),
        ),
      ),
    );

    expect(find.byType(ColoredBox), findsWidgets);
  });
}
