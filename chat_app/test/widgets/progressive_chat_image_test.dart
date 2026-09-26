import 'dart:async';
import 'dart:typed_data';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:chat_app/widgets/authenticated_image.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/widgets/progressive_chat_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fake_e2ee_server.dart';

/// 16:9 的真 PNG（只用来定气泡尺寸：测试里不真正解码）。
Uint8List _png() => Uint8List.fromList(
    img.encodePng(img.Image(width: 160, height: 90), level: 1));

Message _image(
  int i, {
  int? fileSize = 400 * 1024,
  bool withThumbnail = true,
  bool withPreview = false,
}) =>
    Message(
      id: '$i',
      content: 'IMG_$i.jpg',
      senderId: 'user2',
      senderName: 'Bob',
      chatRoomId: 'room1',
      type: MessageType.image,
      status: MessageStatus.sent,
      timestamp: DateTime(2026, 9, 26, 10, i),
      fileUrl: '/api/files/chat/orig-$i.jpg',
      fileName: 'IMG_$i.jpg',
      fileSize: fileSize,
      fileType: 'image/jpeg',
      thumbnailUrl: withThumbnail ? '/api/files/chat/thumb-$i.jpg' : null,
      previewUrl: withPreview ? '/api/files/chat/preview-$i.jpg' : null,
    );

/// 记下每次取图的地址；每个地址返回一份独立的字节，方便认出屏幕上画的是哪张。
class _FakeLoader {
  _FakeLoader({this.holdSharp = false});

  /// true：缩略图以外的请求挂着，由测试手动放行（看并发和顺序）。
  final bool holdSharp;
  final List<String> requested = [];
  final Map<String, Uint8List> bytes = {};
  final Map<String, Completer<Uint8List>> held = {};
  int inFlight = 0;
  int maxInFlight = 0;

  Uint8List bytesFor(String url) => bytes.putIfAbsent(url, _png);

  Future<Uint8List> call(String url) async {
    requested.add(url);
    if (!holdSharp || url.contains('/thumb-')) return bytesFor(url);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final completer = held[url] = Completer<Uint8List>();
    try {
      return await completer.future;
    } finally {
      inFlight--;
    }
  }

  void release(String url) => held[url]!.complete(bytesFor(url));

  /// 同一个函数对象（气泡按加载器区分缓存，每次 `loader.call` 取出来的不是同一个对象）。
  late final ImageBytesLoader fn = call;

  List<String> get sharpRequests =>
      requested.where((url) => !url.contains('/thumb-')).toList();
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Widget _bubble(Message message, _FakeLoader loader) => MessageBubble(
      key: ValueKey('bubble-${message.id}'),
      message: message,
      isMe: false,
      imageLoader: loader.fn,
    );

/// 屏幕上画的图（按层从下到上）的字节。
List<Uint8List> _shownBytes(WidgetTester tester, {Finder? within}) {
  final images = find.descendant(
    of: within ?? find.byType(MessageBubble),
    matching: find.byType(Image),
  );
  return tester
      .widgetList<Image>(images)
      .map((image) => (image.image as MemoryImage).bytes)
      .toList();
}

Finder _sharpLayer() => find.byKey(const ValueKey('chat-image-sharp'));
Finder _thumbnailLayer() => find.byKey(const ValueKey('chat-image-thumbnail'));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  setUp(MessageBubble.clearImageCacheForTesting);
  tearDown(() => AuthenticatedImage.bytesTransformer = null);

  testWidgets(
      'shows the thumbnail first, then swaps to the original once the bubble '
      'has been on screen for a moment', (tester) async {
    final loader = _FakeLoader();
    await tester.pumpWidget(_host(_bubble(_image(1), loader)));
    await _settle(tester);

    expect(loader.requested, ['/api/files/chat/thumb-1.jpg']);
    expect(_shownBytes(tester), [loader.bytesFor('/api/files/chat/thumb-1.jpg')]);

    await tester.pump(const Duration(milliseconds: 200));
    expect(loader.requested, ['/api/files/chat/thumb-1.jpg'],
        reason: '刚上屏不马上下清晰图（快速滑过的不下）');

    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(loader.requested,
        ['/api/files/chat/thumb-1.jpg', '/api/files/chat/orig-1.jpg'],
        reason: '400 KB 的正常压缩图：清晰图就是原图');
    // 清晰图叠在缩略图上淡入（解码出第一帧之前下面还是缩略图）。
    expect(_sharpLayer(), findsOneWidget);
    expect(_shownBytes(tester), [
      loader.bytesFor('/api/files/chat/thumb-1.jpg'),
      loader.bytesFor('/api/files/chat/orig-1.jpg'),
    ]);
    final sharp = tester.widget<Image>(_sharpLayer());
    expect(sharp.filterQuality, FilterQuality.medium);
    expect(tester.widget<Image>(_thumbnailLayer()).filterQuality,
        FilterQuality.high,
        reason: '放大显示的缩略图用高质量插值');
  });

  testWidgets(
      'big originals upgrade to the server preview, never the multi-MB file; '
      'without a preview they stay on the thumbnail', (tester) async {
    final loader = _FakeLoader();
    await tester.pumpWidget(_host(SingleChildScrollView(
      child: Column(children: [
        _bubble(
            _image(1, fileSize: 4 * 1024 * 1024, withPreview: true), loader),
        _bubble(_image(2, fileSize: 4 * 1024 * 1024), loader),
      ]),
    )));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);

    expect(loader.requested, unorderedEquals([
      '/api/files/chat/thumb-1.jpg',
      '/api/files/chat/thumb-2.jpg',
      '/api/files/chat/preview-1.jpg',
    ]));
    expect(loader.requested, isNot(contains('/api/files/chat/orig-1.jpg')));
    expect(loader.requested, isNot(contains('/api/files/chat/orig-2.jpg')));
  });

  testWidgets(
      'fast scrolling does not queue downloads; only bubbles that stay on '
      'screen upgrade, not the ones prebuilt below the viewport',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loader = _FakeLoader();
    final messages = [for (var i = 0; i < 40; i++) _image(i)];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          itemCount: messages.length,
          itemBuilder: (_, i) => _bubble(messages[i], loader),
        ),
      ),
    ));
    await _settle(tester);

    // 一路快速往下翻：每次拖动之间不到停稳的时间。
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(loader.sharpRequests, isEmpty, reason: '滑动中一张清晰图都不下');
    expect(
        loader.requested.where((url) => url.contains('/thumb-')).length,
        greaterThan(10),
        reason: '缩略图照常加载');

    // 停下来：只有屏幕上的换清晰图。
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);

    final viewport = tester.getRect(find.byType(ListView));
    final onScreen = <String>{};
    final prebuilt = <String>{};
    for (final element
        in find.byType(ProgressiveChatImage, skipOffstage: false).evaluate()) {
      final image = element.widget as ProgressiveChatImage;
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      (rect.overlaps(viewport) ? onScreen : prebuilt)
          .add(image.url.replaceFirst('/thumb-', '/orig-'));
    }
    expect(onScreen, isNotEmpty);
    expect(prebuilt, isNotEmpty, reason: '列表在屏幕外预先建好的气泡');
    expect(loader.sharpRequests.toSet(), onScreen);
    expect(loader.sharpRequests.toSet().intersection(prebuilt), isEmpty);
  });

  testWidgets(
      'at most two sharp downloads at a time, newest queued first; queued ones '
      'are dropped when their bubble goes away', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loader = _FakeLoader(holdSharp: true);
    final messages = [for (var i = 0; i < 6; i++) _image(i)];

    await tester.pumpWidget(_host(SingleChildScrollView(
      child: Column(children: [for (final m in messages) _bubble(m, loader)]),
    )));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);

    // 六张同时停在屏幕上：先到先下两张，其余排队。
    expect(loader.sharpRequests,
        ['/api/files/chat/orig-0.jpg', '/api/files/chat/orig-1.jpg']);
    expect(loader.maxInFlight, 2);

    // 空出一个位置：排队的里面最后排进来的先下（用户此刻看着的图先下）。
    loader.release('/api/files/chat/orig-0.jpg');
    await _settle(tester);
    expect(loader.sharpRequests.last, '/api/files/chat/orig-5.jpg');
    expect(loader.maxInFlight, 2);

    // 还在排队的 2、3 的气泡没了：撤掉，不再下载。
    await tester.pumpWidget(_host(SingleChildScrollView(
      child: Column(children: [
        for (final m in [...messages.sublist(0, 2), ...messages.sublist(4)])
          _bubble(m, loader),
      ]),
    )));
    loader.release('/api/files/chat/orig-1.jpg');
    await _settle(tester);
    expect(loader.sharpRequests.last, '/api/files/chat/orig-4.jpg');
    loader.release('/api/files/chat/orig-5.jpg');
    loader.release('/api/files/chat/orig-4.jpg');
    await _settle(tester);
    expect(loader.sharpRequests, [
      '/api/files/chat/orig-0.jpg',
      '/api/files/chat/orig-1.jpg',
      '/api/files/chat/orig-5.jpg',
      '/api/files/chat/orig-4.jpg',
    ]);
    expect(loader.maxInFlight, 2);
    expect(ChatImageUpgradeQueue.shared.running, 0);
    expect(ChatImageUpgradeQueue.shared.waiting, 0);
  });

  testWidgets(
      'a queued download whose bubble was scrolled out of view is skipped when '
      'its turn comes', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loader = _FakeLoader(holdSharp: true);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final messages = [for (var i = 0; i < 40; i++) _image(i)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemCount: messages.length,
          itemBuilder: (_, i) => _bubble(messages[i], loader),
        ),
      ),
    ));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
    // 屏幕上三张：前两张在下，第三张排队。
    expect(loader.sharpRequests,
        ['/api/files/chat/orig-0.jpg', '/api/files/chat/orig-1.jpg']);
    expect(ChatImageUpgradeQueue.shared.waiting, 1);

    // 往下滚一点：第三张刚好滑出屏幕上沿（还在预加载区里，没销毁）。
    final viewport = tester.getRect(find.byType(ListView));
    final third = tester.getRect(find.byKey(const ValueKey('bubble-2')));
    controller.jumpTo(controller.offset + third.bottom - viewport.top + 1);
    await tester.pump();
    expect(find.byKey(const ValueKey('bubble-2'), skipOffstage: false),
        findsOneWidget);

    loader.release('/api/files/chat/orig-0.jpg');
    await _settle(tester);
    expect(loader.sharpRequests,
        ['/api/files/chat/orig-0.jpg', '/api/files/chat/orig-1.jpg'],
        reason: '轮到第三张时它已经不在屏幕上：跳过');
    expect(ChatImageUpgradeQueue.shared.waiting, 0);
    loader.release('/api/files/chat/orig-1.jpg');
    await _settle(tester);
  });

  testWidgets(
      'scrolling back to an upgraded image shows the sharp one straight from '
      'the cache (no spinner, no thumbnail flash, no new download)',
      (tester) async {
    final loader = _FakeLoader();
    await tester.pumpWidget(_host(_bubble(_image(1), loader)));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
    expect(loader.requested, hasLength(2));

    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(_host(_bubble(_image(1), loader)));

    // 第一帧就是清晰图。
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_thumbnailLayer(), findsNothing);
    expect(_shownBytes(tester), [loader.bytesFor('/api/files/chat/orig-1.jpg')]);
    await tester.pump(const Duration(seconds: 1));
    expect(loader.requested, hasLength(2));
  });

  testWidgets('messages without a thumbnail keep loading the original only',
      (tester) async {
    final loader = _FakeLoader();
    await tester.pumpWidget(
        _host(_bubble(_image(1, withThumbnail: false), loader)));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(loader.requested, ['/api/files/chat/orig-1.jpg']);
  });

  testWidgets(
      'encrypted DM: the big-original preview is fetched as ciphertext and '
      'decrypted with its own key from the envelope', (tester) async {
    final chat = Chat(
      id: '42',
      name: 'dm',
      type: ChatType.private,
      createdAt: DateTime(2026),
    );
    final original = Uint8List(Message.sharpOriginalMaxBytes + 1024);
    final thumbnail = _png();
    final preview = _png();
    late EncryptionService bob;
    late E2eeSealedFile sealed;
    await tester.runAsync(() async {
      final server = FakeE2eeServer()
        ..passwords['1'] = 'alice-pw'
        ..passwords['2'] = 'bob-pw'
        ..roomMembers['42'] = ['1', '2'];
      final alice = e2eeDevice(server, '1');
      bob = e2eeDevice(server, '2');
      await alice.enable('alice-pw');
      await bob.enable('bob-pw');
      await bob.roomState(chat, refresh: true);
      sealed = (await alice.sealFile(
        chat,
        name: 'IMG_0001.jpg',
        mimeType: 'image/jpeg',
        kind: 'image',
        readBytes: () async => original,
        readThumbnail: () async => thumbnail,
        makePreview: (_) async => preview,
      ))!;
    });
    addTearDown(() => Message.contentRevealer = null);
    expect(sealed.previewCiphertext, isNotNull);

    final revealed = bob.reveal(Message.fromJson({
      'id': 700,
      'content': kE2eeServerPlaceholder,
      'senderId': 1,
      'chatRoomId': 42,
      'messageType': 'FILE',
      'fileUrl': '/api/files/chat/photo.bin',
      'thumbnailUrl': '/api/files/chat/thumb.bin',
      'previewUrl': '/api/files/chat/preview.bin',
      'encryptedContent': sealed.envelope,
      'encryptionVersion': kE2eeEncryptionVersion,
      'createdAt': '2026-09-26T10:00:00',
    }));
    expect(revealed.sharpImageUrl, '/api/files/chat/preview.bin');
    AuthenticatedImage.bytesTransformer = bob.openDownloadedFile;

    final served = {
      '/api/files/chat/thumb.bin': sealed.thumbnailCiphertext!,
      '/api/files/chat/preview.bin': sealed.previewCiphertext!,
      '/api/files/chat/photo.bin': sealed.ciphertext,
    };
    final requested = <String>[];
    await tester.pumpWidget(_host(MessageBubble(
      message: revealed,
      isMe: false,
      imageLoader: (url) async {
        requested.add(url);
        return served[url]!;
      },
    )));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(requested,
        ['/api/files/chat/thumb.bin', '/api/files/chat/preview.bin']);
    expect(_shownBytes(tester).last, preview, reason: '显示的是解密后的中图');
    expect(_shownBytes(tester).first, thumbnail);
  });

  test('queue: cancelled tickets never run, LIFO order, cap respected',
      () async {
    final queue = ChatImageUpgradeQueue(maxConcurrent: 2);
    final started = <int>[];
    final gates = <int, Completer<void>>{};
    ChatImageUpgradeTicket add(int i) => queue.schedule(() {
          started.add(i);
          return (gates[i] = Completer<void>()).future;
        });

    add(1);
    add(2);
    final three = add(3);
    add(4);
    add(5);
    expect(started, [1, 2]);
    three.cancel();
    gates[2]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2, 5]);
    gates[1]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2, 5, 4]);
    gates[5]!.complete();
    gates[4]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2, 5, 4], reason: '撤掉的 3 不会再跑');
    expect(queue.running, 0);
  });

  test('sharpImageUrl: modest original, big original with/without preview',
      () {
    expect(_image(1).sharpImageUrl, '/api/files/chat/orig-1.jpg');
    expect(
        _image(1, fileSize: Message.sharpOriginalMaxBytes).sharpImageUrl,
        '/api/files/chat/orig-1.jpg');
    expect(
        _image(1, fileSize: Message.sharpOriginalMaxBytes + 1, withPreview: true)
            .sharpImageUrl,
        '/api/files/chat/preview-1.jpg');
    expect(
        _image(1, fileSize: Message.sharpOriginalMaxBytes + 1).sharpImageUrl,
        isNull);
    expect(_image(1, fileSize: null).sharpImageUrl, isNull,
        reason: '不知道原图多大就不自动下');
    expect(_image(1, withThumbnail: false).sharpImageUrl, isNull,
        reason: '气泡本来就显示原图');
    final json = _image(1, withPreview: true).toJson();
    expect(Message.fromJson(json).previewUrl, '/api/files/chat/preview-1.jpg');
    expect(
        Message.fromJson({...json, 'previewUrl': null, 'preview_url': 'x.jpg'})
            .previewUrl,
        'x.jpg');
  });
}
