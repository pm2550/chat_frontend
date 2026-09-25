import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/screens/chat/chat_file_center_screen.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/widgets/authenticated_image.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Message _image({
  String id = '1',
  String? thumbnailUrl,
  MessageType type = MessageType.image,
}) =>
    Message(
      id: id,
      content: 'IMG_0001.jpg',
      senderId: 'user2',
      senderName: 'Bob',
      chatRoomId: 'room1',
      type: type,
      status: MessageStatus.sent,
      timestamp: DateTime(2026, 9, 25, 10),
      fileUrl: '/api/files/chat/original.jpg',
      fileName: 'IMG_0001.jpg',
      fileSize: 2900000,
      fileType: 'image/jpeg',
      thumbnailUrl: thumbnailUrl,
      imageGenStatus: type == MessageType.imageGeneration ? 'DONE' : null,
      imageGenUrl: type == MessageType.imageGeneration
          ? '/api/files/chat/original.jpg'
          : null,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  setUp(MessageBubble.clearImageCacheForTesting);

  testWidgets(
      'bubble loads the small thumbnail, tapping still opens the original',
      (tester) async {
    final requested = <String>[];
    Message? opened;

    await tester.pumpWidget(_host(MessageBubble(
      message: _image(thumbnailUrl: '/api/files/chat/thumb.jpg'),
      isMe: false,
      imageLoader: (url) async {
        requested.add(url);
        return _pixel;
      },
      onOpenAttachment: (message) async => opened = message,
    )));
    await tester.pumpAndSettle();

    expect(requested, ['/api/files/chat/thumb.jpg'], reason: '气泡不下载原图');
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(opened!.fileUrl, '/api/files/chat/original.jpg',
        reason: '点开大图用的还是原图地址');
  });

  testWidgets('messages without a thumbnail (old ones) still load the original',
      (tester) async {
    final requested = <String>[];

    await tester.pumpWidget(_host(MessageBubble(
      message: _image(),
      isMe: false,
      imageLoader: (url) async {
        requested.add(url);
        return _pixel;
      },
    )));
    await tester.pumpAndSettle();

    expect(requested, ['/api/files/chat/original.jpg']);
  });

  testWidgets('AI image results also show their thumbnail', (tester) async {
    final requested = <String>[];

    await tester.pumpWidget(_host(MessageBubble(
      message: _image(
        type: MessageType.imageGeneration,
        thumbnailUrl: '/api/files/chat/gen-thumb.jpg',
      ),
      isMe: false,
      imageLoader: (url) async {
        requested.add(url);
        return _pixel;
      },
    )));
    await tester.pumpAndSettle();

    expect(requested, ['/api/files/chat/gen-thumb.jpg']);
  });

  test('thumbnailUrl round-trips through JSON (server payload and local cache)',
      () {
    final message = Message.fromJson({
      'id': 9,
      'content': 'IMG.jpg',
      'senderId': 2,
      'chatRoomId': 3,
      'messageType': 'IMAGE',
      'fileUrl': '/api/files/chat/a.jpg',
      'thumbnailUrl': '/api/files/chat/a-thumb.jpg',
      'createdAt': '2026-09-25T10:00:00',
    });
    expect(message.thumbnailUrl, '/api/files/chat/a-thumb.jpg');
    expect(message.bubbleImageUrl, '/api/files/chat/a-thumb.jpg');
    expect(message.previewImageUrl, '/api/files/chat/a.jpg');
    expect(Message.fromJson(message.toJson()).thumbnailUrl,
        '/api/files/chat/a-thumb.jpg');
    expect(message.copyWith(clearThumbnailUrl: true).bubbleImageUrl,
        '/api/files/chat/a.jpg');
  });

  testWidgets(
      'file center (list and desktop grid) loads thumbnails, not originals',
      (tester) async {
    Future<void> open() async {
      await tester.pumpWidget(MaterialApp(
        home: ChatFileCenterScreen(
          chatRoomId: 'room1',
          chatRoomName: 'Room',
          chatService: _FileCenterService([
            _image(thumbnailUrl: '/api/files/chat/thumb.jpg'),
            _image(id: '2'),
          ]),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    Iterable<String> imageUrls() => tester
        .widgetList<AuthenticatedImage>(find.byType(AuthenticatedImage))
        .map((image) => image.url);

    await open();
    expect(imageUrls(), ['/api/files/chat/thumb.jpg'],
        reason: '列表里只加载预览图；没有预览图的老消息仍显示图标，不下载原图');

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const SizedBox());
    await open();
    final cards = tester
        .widgetList<PMAttachmentCard>(find.byType(PMAttachmentCard))
        .map((card) => card.thumbnail)
        .toList();
    expect(cards, contains('/api/files/chat/thumb.jpg'));
    expect(cards, isNot(contains('/api/files/chat/original.jpg')));
  });
}

class _FileCenterService extends ChatDataService {
  _FileCenterService(this.messages);

  final List<Message> messages;

  @override
  Future<MessagePage> getFileMessages(
    String chatRoomId, {
    MessageType? type,
    int page = 0,
    int size = 50,
  }) async {
    return MessagePage(
      messages: messages,
      currentPage: 0,
      totalPages: 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: false,
    );
  }
}
