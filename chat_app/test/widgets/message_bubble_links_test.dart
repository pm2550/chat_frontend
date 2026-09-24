import 'package:chat_app/models/message.dart';
import 'package:chat_app/utils/link_utils.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _RecordingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

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

Message _message(
  String content, {
  MessageType type = MessageType.text,
  LinkPreview? linkPreview,
}) {
  return Message(
    id: '1',
    content: content,
    senderId: 'user2',
    senderName: '好友',
    chatRoomId: 'room1',
    type: type,
    status: MessageStatus.sent,
    timestamp: DateTime(2026, 1, 1),
    linkPreview: linkPreview,
  );
}

void main() {
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

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('LinkUtils', () {
    test('finds http(s) links and trims trailing punctuation and CJK text', () {
      final links = LinkUtils.findUrls(
        '看这个https://example.com/a?b=1。还有 http://x.org/p, 结束',
      );
      expect(links.map((l) => l.url), [
        'https://example.com/a?b=1',
        'http://x.org/p',
      ]);
    });

    test('never treats other schemes as links', () {
      expect(LinkUtils.findUrls('javascript:alert(1) file:///etc/passwd'),
          isEmpty);
      expect(LinkUtils.safeWebUri('javascript:alert(1)'), isNull);
      expect(LinkUtils.safeWebUri('https://'), isNull);
    });

    test('location map uri from url, coordinates, or nothing', () {
      expect(
        LinkUtils.mapUriForLocation('公司 https://maps.example.com/p?q=1')
            .toString(),
        'https://maps.example.com/p?q=1',
      );
      final coords = LinkUtils.mapUriForLocation('会议室 31.2304, 121.4737');
      expect(coords?.host, 'www.openstreetmap.org');
      expect(coords?.queryParameters['mlat'], '31.2304');
      expect(coords?.queryParameters['mlon'], '121.4737');
      expect(LinkUtils.mapUriForLocation('公司会议室'), isNull);
      expect(LinkUtils.mapUriForLocation('坐标 123.0, 500.0'), isNull);
    });
  });

  testWidgets('tapping a URL in a user message opens it externally',
      (tester) async {
    await tester.pumpWidget(wrap(MessageBubble(
      message: _message('看这个 https://example.com/a?b=1。'),
      isMe: false,
    )));
    await tester.pump();

    final link = find.byKey(const ValueKey(
      'message-link-https://example.com/a?b=1',
    ));
    expect(link, findsOneWidget);
    await tester.tap(link);
    await tester.pump();

    expect(launcher.launched, ['https://example.com/a?b=1']);
  });

  testWidgets('mentions stay tappable next to links', (tester) async {
    final mentioned = <String>[];
    await tester.pumpWidget(wrap(MessageBubble(
      message: _message('@alice 看 https://example.com/@bob 这里'),
      isMe: false,
      onMentionTap: mentioned.add,
    )));
    await tester.pump();

    await tester.tap(find.text('@alice'));
    await tester.pump();
    expect(mentioned, ['alice']);
    // The @bob inside the URL belongs to the link, not a mention.
    expect(find.text('@bob'), findsNothing);
    await tester.tap(find.byKey(const ValueKey(
      'message-link-https://example.com/@bob',
    )));
    await tester.pump();
    expect(launcher.launched, ['https://example.com/@bob']);
    expect(mentioned, ['alice']);
  });

  testWidgets('long-press on a link still reaches the bubble long-press',
      (tester) async {
    var longPressed = 0;
    await tester.pumpWidget(wrap(GestureDetector(
      onLongPress: () => longPressed += 1,
      child: MessageBubble(
        message: _message('https://example.com/copy-me'),
        isMe: false,
      ),
    )));
    await tester.pump();

    await tester.longPress(find.byKey(const ValueKey(
      'message-link-https://example.com/copy-me',
    )));
    await tester.pump();

    expect(longPressed, 1);
    expect(launcher.launched, isEmpty);
  });

  testWidgets('link preview card opens its URL', (tester) async {
    await tester.pumpWidget(wrap(MessageBubble(
      message: _message(
        'https://example.com/post',
        linkPreview: const LinkPreview(
          url: 'https://example.com/post',
          title: '一篇文章',
        ),
      ),
      isMe: false,
    )));
    await tester.pump();

    await tester.tap(find.text('一篇文章'));
    await tester.pump();

    expect(launcher.launched, ['https://example.com/post']);
  });

  testWidgets('location with coordinates opens a map; name-only does not',
      (tester) async {
    await tester.pumpWidget(wrap(Column(
      children: [
        MessageBubble(
          key: const ValueKey('with-coords'),
          message: _message('会议室 31.2304,121.4737', type: MessageType.location),
          isMe: false,
        ),
        MessageBubble(
          key: const ValueKey('name-only'),
          message: _message('公司会议室', type: MessageType.location),
          isMe: false,
        ),
      ],
    )));
    await tester.pump();

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('with-coords')),
      matching: find.byKey(const ValueKey('message-location-card')),
    ));
    await tester.pump();
    expect(launcher.launched, hasLength(1));
    expect(launcher.launched.single, contains('openstreetmap.org'));

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('name-only')),
      matching: find.byKey(const ValueKey('message-location-card')),
    ));
    await tester.pump();
    expect(launcher.launched, hasLength(1));
  });
}
