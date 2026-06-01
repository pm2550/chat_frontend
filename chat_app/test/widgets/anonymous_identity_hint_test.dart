import 'package:chat_app/services/anonymous_service.dart';
import 'package:chat_app/widgets/anonymous_identity_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('AnonymousIdentityHint', () {
    testWidgets('shows current anonymous identity when visible',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        AnonymousIdentityHint(
          identity: AnonymousIdentity(
            anonymousName: '神秘小象',
            anonymousAvatar: '#7C3AED',
          ),
          quota: const AnonymousQuota(used: 1, remaining: 2),
          onReroll: () {},
        ),
      ));

      expect(find.byKey(const ValueKey('anonymous-identity-hint')),
          findsOneWidget);
      expect(find.text('当前匿名身份：'), findsOneWidget);
      expect(find.text('神秘小象'), findsOneWidget);
      expect(find.text('· 今天还可换 2/3 次'), findsOneWidget);
      expect(find.text('换一个'), findsOneWidget);
    });

    testWidgets('hides when anonymous toggle is off', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        AnonymousIdentityHint(
          visible: false,
          identity: AnonymousIdentity(
            anonymousName: '神秘小象',
            anonymousAvatar: '#7C3AED',
          ),
          quota: const AnonymousQuota(used: 1, remaining: 2),
          onReroll: () {},
        ),
      ));

      expect(
          find.byKey(const ValueKey('anonymous-identity-hint')), findsNothing);
      expect(find.text('神秘小象'), findsNothing);
    });

    testWidgets('disabled state actually blocks reroll service invocation',
        (tester) async {
      var serviceInvocations = 0;
      await tester.pumpWidget(buildTestWidget(
        AnonymousIdentityHint(
          identity: AnonymousIdentity(
            anonymousName: '快乐企鹅',
            anonymousAvatar: '#4ECDC4',
          ),
          quota: const AnonymousQuota(used: 3, remaining: 0),
          onReroll: () => serviceInvocations++,
        ),
      ));

      expect(find.text('· 今天还可换 0/3 次'), findsOneWidget);
      await tester.tap(find.text('换一个'));
      await tester.pump();

      expect(
        serviceInvocations,
        0,
        reason: 'onReroll must NOT fire when button disabled',
      );
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('after reroll, name and remaining re-render together',
        (tester) async {
      var identity = AnonymousIdentity(
        anonymousName: '智慧浣熊',
        anonymousAvatar: '#7C3AED',
      );
      var quota = const AnonymousQuota(used: 0, remaining: 3);

      await tester.pumpWidget(buildTestWidget(
        StatefulBuilder(
          builder: (context, setState) => AnonymousIdentityHint(
            identity: identity,
            quota: quota,
            onReroll: () {
              setState(() {
                identity = AnonymousIdentity(
                  anonymousName: '沉稳小鹿',
                  anonymousAvatar: '#4ECDC4',
                );
                quota = const AnonymousQuota(used: 1, remaining: 2);
              });
            },
          ),
        ),
      ));

      expect(find.text('智慧浣熊'), findsOneWidget);
      expect(find.text('· 今天还可换 3/3 次'), findsOneWidget);

      await tester.tap(find.text('换一个'));
      await tester.pumpAndSettle();

      expect(find.text('沉稳小鹿'), findsOneWidget);
      expect(find.text('· 今天还可换 2/3 次'), findsOneWidget);
      expect(find.text('智慧浣熊'), findsNothing);
      expect(find.text('· 今天还可换 3/3 次'), findsNothing);
    });
  });
}
