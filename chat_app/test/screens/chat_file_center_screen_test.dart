import 'package:chat_app/models/message.dart';
import 'package:chat_app/screens/chat/chat_file_center_screen.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/widgets/chat_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders file messages and downloads selected file',
      (tester) async {
    final service = FakeFileCenterChatService();

    await tester.pumpWidget(MaterialApp(
      home: ChatFileCenterScreen(
        chatRoomId: '42',
        chatRoomName: 'Project Room',
        chatService: service,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('doc.pdf'), findsOneWidget);

    await tester.tap(find.text('doc.pdf'));
    await tester.pumpAndSettle();

    expect(service.downloadedIds, ['2']);
    expect(find.text('已取回 doc.pdf (3 B)'), findsOneWidget);
  });

  testWidgets('tapping image opens preview instead of saving immediately',
      (tester) async {
    final service = FakeFileCenterChatService();

    await tester.pumpWidget(MaterialApp(
      home: ChatFileCenterScreen(
        chatRoomId: '42',
        chatRoomName: 'Project Room',
        chatService: service,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('photo.png').first);
    await tester.pumpAndSettle();

    expect(service.downloadedIds, ['1']);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('保存图片'), findsOneWidget);
    expect(find.textContaining('已保存'), findsNothing);
  });

  testWidgets('tapping video opens preview instead of saving immediately',
      (tester) async {
    final service = FakeFileCenterChatService();

    await tester.pumpWidget(MaterialApp(
      home: ChatFileCenterScreen(
        chatRoomId: '42',
        chatRoomName: 'Project Room',
        chatService: service,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ChatVideoThumbnail), findsOneWidget);
    await tester.tap(find.text('clip.mp4').first);
    await tester.pump();

    expect(service.downloadedIds, ['3']);
    expect(find.byTooltip('保存视频'), findsOneWidget);
    expect(find.textContaining('已取回'), findsNothing);
    expect(find.textContaining('已保存'), findsNothing);
  });

  testWidgets('filters file center by image type', (tester) async {
    final service = FakeFileCenterChatService();

    await tester.pumpWidget(MaterialApp(
      home: ChatFileCenterScreen(
        chatRoomId: '42',
        chatRoomName: 'Project Room',
        chatService: service,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();

    expect(service.requestedTypes.last, MessageType.image);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('doc.pdf'), findsNothing);
  });

  testWidgets('desktop grid keeps image file details visible', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final service = FakeFileCenterChatService();

    await tester.pumpWidget(MaterialApp(
      home: ChatFileCenterScreen(
        chatRoomId: '42',
        chatRoomName: 'Project Room',
        chatService: service,
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('2 B · Alice'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

class FakeFileCenterChatService extends ChatDataService {
  final requestedTypes = <MessageType?>[];
  final downloadedIds = <String>[];

  final messages = [
    Message(
      id: '1',
      content: 'photo.png',
      senderId: '7',
      senderName: 'Alice',
      chatRoomId: '42',
      type: MessageType.image,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:00:00'),
      fileUrl: '/api/files/chat/photo.png',
      fileName: 'photo.png',
      fileSize: 2,
      fileType: 'image/png',
    ),
    Message(
      id: '2',
      content: 'doc.pdf',
      senderId: '8',
      senderName: 'Bob',
      chatRoomId: '42',
      type: MessageType.file,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:01:00'),
      fileUrl: '/api/files/chat/doc.pdf',
      fileName: 'doc.pdf',
      fileSize: 3,
      fileType: 'application/pdf',
    ),
    Message(
      id: '3',
      content: 'clip.mp4',
      senderId: '9',
      senderName: 'Carol',
      chatRoomId: '42',
      type: MessageType.video,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      fileUrl: '/api/files/chat/clip.mp4',
      fileName: 'clip.mp4',
      fileSize: 4,
      fileType: 'video/mp4',
    ),
  ];

  @override
  Future<MessagePage> getFileMessages(
    String chatRoomId, {
    MessageType? type,
    int page = 0,
    int size = 50,
  }) async {
    requestedTypes.add(type);
    final filtered = type == null
        ? messages
        : messages.where((m) => m.type == type).toList();
    return MessagePage(
      messages: filtered,
      currentPage: page,
      totalPages: 1,
      totalElements: filtered.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<DownloadedChatFile> downloadFile(Message message) async {
    downloadedIds.add(message.id);
    return DownloadedChatFile(
      name: message.fileName ?? message.content,
      bytes: const [1, 2, 3],
      mimeType: message.fileType,
    );
  }
}
