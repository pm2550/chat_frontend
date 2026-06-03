import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/models/message.dart';

/// Records every URL the app tries to open so tests can assert that dangerous
/// schemes are NEVER launched. Both the modern (`launchUrl`) and legacy (`launch`)
/// platform entry points funnel into [launched].
class _RecordingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }
}

void main() {
  Message botMessage({
    required String content,
    MessageContentFormat contentFormat = MessageContentFormat.plain,
  }) {
    return Message(
      id: '1',
      content: content,
      senderId: 'user1',
      senderName: 'owner',
      botConfigId: '7',
      botSenderId: '7',
      botName: 'Searcher',
      chatRoomId: 'room1',
      type: MessageType.text,
      contentFormat: contentFormat,
      status: MessageStatus.sent,
      timestamp: DateTime(2026, 1, 1),
    );
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders a GFM table for a MARKDOWN bot message', (tester) async {
    final message = botMessage(
      content: '| a | b |\n|---|---|\n| 1 | 2 |',
      contentFormat: MessageContentFormat.markdown,
    );

    await tester.pumpWidget(wrap(MessageBubble(message: message, isMe: false)));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(Table), findsWidgets);
  });

  testWidgets('plain bot message does NOT use the markdown renderer',
      (tester) async {
    final message = botMessage(content: 'just plain text');

    await tester.pumpWidget(wrap(MessageBubble(message: message, isMe: false)));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.textContaining('just plain text'), findsWidgets);
  });

  group('markdown link scheme whitelist (XSS/phishing guard)', () {
    late _RecordingUrlLauncher launcher;
    late UrlLauncherPlatform original;

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = _RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    tearDown(() {
      UrlLauncherPlatform.instance = original;
    });

    // The exact payloads called out in the adversarial review.
    const dangerous = <String>[
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      ' javascript:alert(1)', // leading whitespace must not smuggle the scheme
      'data:text/html,<script>alert(1)</script>',
      'file:///etc/passwd',
      'vbscript:msgbox(1)',
      'blob:https://evil/x',
      '/relative/path', // no scheme
      '', // empty
    ];

    for (final href in dangerous) {
      test('does NOT launch dangerous href: "$href"', () async {
        await MessageBubble.handleMarkdownLinkTap(href);
        expect(launcher.launched, isEmpty,
            reason: 'dangerous scheme "$href" must never reach launchUrl');
      });
    }

    test('DOES launch allowed schemes', () async {
      await MessageBubble.handleMarkdownLinkTap('https://example.com/x');
      await MessageBubble.handleMarkdownLinkTap('http://example.com');
      await MessageBubble.handleMarkdownLinkTap('mailto:a@b.com');
      await MessageBubble.handleMarkdownLinkTap('tel:+123');
      expect(launcher.launched, hasLength(4));
      expect(launcher.launched.first, 'https://example.com/x');
    });

    testWidgets(
        'a MARKDOWN bot message carrying a javascript: link renders but does '
        'not auto-launch', (tester) async {
      final message = botMessage(
        content: '[click me](javascript:alert(1)) and '
            '![x](javascript:alert(2))',
        contentFormat: MessageContentFormat.markdown,
      );

      await tester
          .pumpWidget(wrap(MessageBubble(message: message, isMe: false)));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      // Rendering a dangerous link must never trigger a launch on its own.
      expect(launcher.launched, isEmpty);
    });
  });
}
