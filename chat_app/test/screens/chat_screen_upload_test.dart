import 'dart:async';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/chat_upload.dart';
import 'package:chat_app/services/image_upload/image_upload_preparer.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:chat_app/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_web_socket_channel.dart';
import 'chat_screen_test.dart' show FakeChatDataService;

/// 一次被测试掌控的上传：测试决定何时报进度、何时成功/失败。
class _ControlledUpload {
  _ControlledUpload(
      this.file, this.clientMessageId, this.onProgress, this.cancelToken);

  final PickedChatFile file;
  final String? clientMessageId;
  final UploadProgressCallback? onProgress;
  final UploadCancelToken? cancelToken;
  final Completer<Message> result = Completer<Message>();
}

class _UploadChatService extends FakeChatDataService {
  // 有一条历史：列表才会渲染出来（旧代码的假"文件 正在输入"就挂在列表末尾）。
  _UploadChatService()
      : super(messages: [
          Message(
            id: '1',
            content: '之前的消息',
            senderId: 'user2',
            senderName: '好友',
            chatRoomId: '1',
            status: MessageStatus.sent,
            timestamp: DateTime.parse('2024-01-01T10:00:00'),
          ),
        ]);

  final List<_ControlledUpload> uploads = [];

  @override
  Future<Message> sendFileMessage(
    String chatRoomId,
    PickedChatFile file, {
    MessageType? messageType,
    Chat? chat,
    String? clientMessageId,
    UploadProgressCallback? onProgress,
    UploadCancelToken? cancelToken,
  }) {
    sentFiles.add(file);
    final upload =
        _ControlledUpload(file, clientMessageId, onProgress, cancelToken);
    uploads.add(upload);
    // 和真实传输一样：被取消就以 UploadCancelledException 结束。
    cancelToken?.whenCancelled.then((_) {
      if (!upload.result.isCompleted) {
        upload.result.completeError(const UploadCancelledException());
      }
    });
    return upload.result.future;
  }
}

Message _serverFile(String id, String name, {String? clientMessageId}) =>
    Message(
      id: id,
      clientMessageId: clientMessageId,
      content: name,
      senderId: 'user1',
      senderName: '我',
      chatRoomId: '1',
      type: MessageType.file,
      status: MessageStatus.sent,
      timestamp: DateTime.now(),
      fileUrl: '/api/files/chat/$name',
      fileName: name,
      fileSize: 2048,
      fileType: 'application/pdf',
    );

/// 发图前的处理由测试掌控：记录每次调用（是不是原图），测试决定何时处理完、结果是什么。
class _ControlledPreparer extends ImageUploadPreparer {
  final List<({PickedChatFile file, bool original})> calls = [];
  final List<Completer<PreparedImageUpload>> results = [];

  @override
  Future<PreparedImageUpload> prepare(
    PickedChatFile file, {
    bool original = false,
  }) {
    calls.add((file: file, original: original));
    final result = Completer<PreparedImageUpload>();
    results.add(result);
    return result.future;
  }
}

PreparedImageUpload _prepared(String name, int size, {int originalSize = 4000000}) =>
    PreparedImageUpload(
      file: PickedChatFile(
        name: name,
        size: size,
        mimeType: 'image/jpeg',
        bytes: List<int>.filled(4, size % 251),
      ),
      originalSize: originalSize,
      outcome: ImagePrepareOutcome.compressed,
    );

const _photo = PickedChatFile(
  name: 'IMG_0001.jpg',
  size: 4000000,
  mimeType: 'image/jpeg',
  bytes: [1, 2, 3],
);

const _doc = PickedChatFile(
  name: 'doc.pdf',
  size: 2048,
  mimeType: 'application/pdf',
  bytes: [1, 2, 3],
);

void main() {
  setUp(() {
    ChatScreen.clearMessageCacheForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  Chat room() => Chat(
        id: '1',
        name: '测试聊天',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T09:00:00'),
        participants: [
          User(
            id: 'user2',
            username: 'friend',
            email: 'friend@example.com',
            displayName: '好友',
            onlineStatus: OnlineStatus.online,
            createdAt: DateTime.parse('2024-01-01T09:00:00'),
          ),
        ],
      );

  Future<(FakeWebSocketChannel, WebSocketService, _UploadChatService)> pump(
    WidgetTester tester, {
    ChatAttachmentPicker? imagePicker,
    ChatAttachmentPicker? filePicker,
    ImageUploadPreparer? preparer,
  }) async {
    final channel = FakeWebSocketChannel();
    final socket = WebSocketService.forTesting(
      authService: SocketAuthService(),
      channelFactory: (_) => channel,
    );
    final service = _UploadChatService();
    final chat = room();
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: RouteSettings(arguments: chat),
          builder: (context) => ChatScreen(
            chatService: service,
            authService: SocketAuthService(),
            webSocketService: socket,
            filePicker: filePicker ?? () async => _doc,
            imagePicker: imagePicker,
            imageUploadPreparer: preparer,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (channel, socket, service);
  }

  Future<void> pickFile(WidgetTester tester, {String entry = '文件'}) async {
    await tester.tap(find.byTooltip('附件'));
    // 进行中的上传气泡有不定进度条动画，pumpAndSettle 等不到静止。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(entry));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester, WebSocketService socket) async {
    socket.disconnect();
    await tester.pumpWidget(const SizedBox());
  }

  Finder uploadBubbles() => find.byWidgetPredicate((widget) =>
      widget.key is ValueKey<String> &&
      RegExp(r'^chat-upload-local-')
          .hasMatch((widget.key as ValueKey<String>).value));

  testWidgets('upload shows an outgoing progress bubble, never "文件 正在输入"',
      (tester) async {
    final (_, socket, service) = await pump(tester);
    await pickFile(tester);

    expect(service.uploads, hasLength(1));
    expect(find.byType(TypingIndicator), findsNothing, reason: '上传不是有人在打字');
    expect(find.textContaining('正在输入'), findsNothing);
    expect(uploadBubbles(), findsOneWidget);
    expect(find.text('doc.pdf'), findsOneWidget);
    expect(find.text('正在发送…'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    service.uploads.single.onProgress!(45, 100);
    await tester.pump();
    expect(find.text('正在发送 45%'), findsOneWidget);
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.45, 0.001));
    expect(find.textContaining('正在输入'), findsNothing);
    await finish(tester, socket);
  });

  testWidgets('no byte progress for 30s says the network is slow',
      (tester) async {
    final (_, socket, service) = await pump(tester);
    await pickFile(tester);
    final upload = service.uploads.single;

    upload.onProgress!(45, 100);
    await tester.pump(const Duration(seconds: 29));
    expect(find.text('正在发送 45%'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('网络较慢，仍在上传… 45%'), findsOneWidget);

    // 又有字节发出去了，提示收回。
    upload.onProgress!(60, 100);
    await tester.pump();
    expect(find.text('正在发送 60%'), findsOneWidget);
    expect(find.textContaining('网络较慢'), findsNothing);

    // 全部发完、在等服务器处理：不算网络慢。
    upload.onProgress!(100, 100);
    await tester.pump(const Duration(seconds: 45));
    expect(find.text('正在发送 100% · 等待服务器确认'), findsOneWidget);
    await finish(tester, socket);
  });

  testWidgets('timeout marks the bubble failed and 重试 re-sends the same file',
      (tester) async {
    final (_, socket, service) = await pump(tester);
    await pickFile(tester);

    service.uploads.single.result
        .completeError(UploadTimeoutException(const Duration(minutes: 2)));
    await tester.pump();

    expect(find.text('发送失败：网络超时'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(service.uploads, hasLength(2));
    expect(service.uploads[1].file, same(_doc), reason: '原样重发同一个文件');
    expect(service.uploads[1].clientMessageId,
        isNot(service.uploads[0].clientMessageId));
    expect(find.text('发送失败：网络超时'), findsNothing);
    expect(uploadBubbles(), findsOneWidget, reason: '旧的失败气泡被新的上传取代');

    service.uploads[1].result.complete(_serverFile('500', 'doc.pdf'));
    await tester.pumpAndSettle();
    expect(uploadBubbles(), findsNothing);
    expect(find.text('[文件] doc.pdf'), findsOneWidget);
    await finish(tester, socket);
  });

  testWidgets('取消 aborts the request and removes the bubble', (tester) async {
    final (_, socket, service) = await pump(tester);
    await pickFile(tester);
    final upload = service.uploads.single;
    upload.onProgress!(10, 100);
    await tester.pump();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(upload.cancelToken!.isCancelled, isTrue, reason: '请求要真的中止');
    expect(uploadBubbles(), findsNothing);
    expect(find.text('doc.pdf'), findsNothing);
    expect(find.textContaining('发送失败'), findsNothing);
    await finish(tester, socket);
  });

  testWidgets('finished upload is replaced by the server message, echo no dup',
      (tester) async {
    final (channel, socket, service) = await pump(tester);
    await pickFile(tester);
    final upload = service.uploads.single;
    expect(upload.clientMessageId, startsWith('local-'));

    upload.result.complete(_serverFile('501', 'doc.pdf'));
    await tester.pumpAndSettle();
    expect(uploadBubbles(), findsNothing);
    expect(find.text('[文件] doc.pdf'), findsOneWidget);

    // 服务器随后把同一条消息推回来（带 clientMessageId）：不能多出一条。
    channel.serverSends({
      'type': 'message',
      'event': 'created',
      'clientMessageId': upload.clientMessageId,
      'message': {
        'id': '501',
        'content': 'doc.pdf',
        'senderId': 'user1',
        'chatRoomId': 1,
        'messageType': 'FILE',
        'messageStatus': 'SENT',
        'fileUrl': '/api/files/chat/doc.pdf',
        'fileName': 'doc.pdf',
        'fileType': 'application/pdf',
        'createdAt': '2024-01-01T10:05:00',
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('[文件] doc.pdf'), findsOneWidget);
    await finish(tester, socket);
  });

  testWidgets(
      'server echo arriving before the REST response settles the bubble',
      (tester) async {
    final (channel, socket, service) = await pump(tester);
    await pickFile(tester);
    final upload = service.uploads.single;
    upload.onProgress!(100, 100);
    await tester.pump();

    // 跨境代理很慢：服务器已经存好并推回，REST 响应还没回来。
    channel.serverSends({
      'type': 'message',
      'event': 'created',
      'clientMessageId': upload.clientMessageId,
      'message': {
        'id': '502',
        'content': 'doc.pdf',
        'senderId': 'user1',
        'chatRoomId': 1,
        'messageType': 'FILE',
        'messageStatus': 'SENT',
        'fileUrl': '/api/files/chat/doc.pdf',
        'fileName': 'doc.pdf',
        'fileType': 'application/pdf',
        'createdAt': '2024-01-01T10:05:00',
      },
    });
    await tester.pumpAndSettle();

    expect(uploadBubbles(), findsNothing);
    expect(find.text('[文件] doc.pdf'), findsOneWidget);
    expect(upload.cancelToken!.isCancelled, isTrue, reason: '正式消息已到，不必再等那个慢响应');
    expect(find.textContaining('发送失败'), findsNothing);
    await finish(tester, socket);
  });

  testWidgets(
      'a late timeout after the echo does not resurrect a failed bubble',
      (tester) async {
    final (channel, socket, service) = await pump(tester);
    await pickFile(tester);
    final first = service.uploads.single;
    first.result
        .completeError(UploadTimeoutException(const Duration(minutes: 2)));
    await tester.pump();
    expect(find.text('发送失败：网络超时'), findsOneWidget);

    // 客户端超时了，但服务器其实收到了：推回的正式消息把失败气泡换掉，不必重发。
    channel.serverSends({
      'type': 'message',
      'event': 'created',
      'clientMessageId': first.clientMessageId,
      'message': {
        'id': '503',
        'content': 'doc.pdf',
        'senderId': 'user1',
        'chatRoomId': 1,
        'messageType': 'FILE',
        'messageStatus': 'SENT',
        'fileUrl': '/api/files/chat/doc.pdf',
        'fileName': 'doc.pdf',
        'createdAt': '2024-01-01T10:05:00',
      },
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('发送失败'), findsNothing);
    expect(uploadBubbles(), findsNothing);
    expect(find.text('[文件] doc.pdf'), findsOneWidget);
    await finish(tester, socket);
  });

  testWidgets('each upload has its own bubble and uploads run concurrently',
      (tester) async {
    final (_, socket, service) = await pump(tester);
    await pickFile(tester);
    await pickFile(tester);

    expect(service.uploads, hasLength(2), reason: '第二个不被第一个挡住');
    expect(uploadBubbles(), findsNWidgets(2));
    service.uploads[0].onProgress!(20, 100);
    service.uploads[1].onProgress!(70, 100);
    await tester.pump();
    expect(find.text('正在发送 20%'), findsOneWidget);
    expect(find.text('正在发送 70%'), findsOneWidget);

    service.uploads[1].result.complete(_serverFile('601', 'doc.pdf'));
    await tester.pumpAndSettle();
    expect(uploadBubbles(), findsOneWidget);
    expect(find.text('正在发送 20%'), findsOneWidget);
    await finish(tester, socket);
  });

  testWidgets(
      'queued attachments get bubbles at once, upload in order, text goes last',
      (tester) async {
    final (channel, socket, service) = await pump(tester);

    const image = PickedChatFile(
      name: 'a.png',
      size: 3,
      mimeType: 'image/png',
      bytes: [1, 2, 3],
    );
    // 用拖放把两个文件排进发送栏。
    final dropTarget = find.byKey(const Key('chat-drop-target'));
    expect(dropTarget, findsOneWidget);
    final DragTarget<List<PickedChatFile>> target = tester.widget(dropTarget);
    target.onAcceptWithDetails!(DragTargetDetails(
      data: const [image, _doc],
      offset: Offset.zero,
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-pending-attachment-1')),
        findsOneWidget);

    await tester.enterText(find.byType(TextField), '看这两个');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
        find.byKey(const ValueKey('chat-pending-attachment-0')), findsNothing);
    expect(uploadBubbles(), findsNWidgets(2), reason: '两个都立刻有气泡');
    expect(find.text('等待发送'), findsOneWidget, reason: '第二个在排队');
    expect(service.uploads, hasLength(1), reason: '按顺序一个一个传');
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, isEmpty, reason: '输入框立刻清空，防止慢网下重复发送');
    expect(channel.sent.where((f) => f['type'] == 'message'), isEmpty,
        reason: '文字排在附件后面');

    service.uploads[0].result.complete(_serverFile('701', 'a.png'));
    await tester.pump();
    await tester.pump();
    expect(service.uploads, hasLength(2));
    expect(service.uploads[1].file.name, 'doc.pdf');
    expect(channel.sent.where((f) => f['type'] == 'message'), isEmpty);

    service.uploads[1].result.complete(_serverFile('702', 'doc.pdf'));
    await tester.pump();
    await tester.pump();
    final text = channel.sent.where((f) => f['type'] == 'message').toList();
    expect(text, hasLength(1));
    expect(text.single['content'], '看这两个');
    await finish(tester, socket);
  });

  testWidgets('相册的图先显示"正在压缩…"，压好后按压缩后的大小上传', (tester) async {
    final preparer = _ControlledPreparer();
    final (_, socket, service) = await pump(
      tester,
      imagePicker: () async => _photo,
      preparer: preparer,
    );

    await pickFile(tester, entry: '相册');

    expect(preparer.calls.single.file.name, 'IMG_0001.jpg');
    expect(preparer.calls.single.original, isFalse);
    expect(uploadBubbles(), findsOneWidget);
    expect(find.text('正在压缩…'), findsOneWidget);
    expect(service.uploads, isEmpty, reason: '压完才上传');

    preparer.results.single.complete(_prepared('IMG_0001.jpg', 400000));
    await tester.pump();
    await tester.pump();

    final upload = service.uploads.single;
    expect(upload.file.size, 400000, reason: '上传的是压缩后的文件');
    expect(find.text('正在压缩…'), findsNothing);
    upload.onProgress!(200000, 400000);
    await tester.pump();
    expect(find.text('正在发送 50%'), findsOneWidget);
    await finish(tester, socket);
  });

  testWidgets('压缩中也能取消：不会再上传', (tester) async {
    final preparer = _ControlledPreparer();
    final (_, socket, service) = await pump(
      tester,
      imagePicker: () async => _photo,
      preparer: preparer,
    );
    await pickFile(tester, entry: '相册');
    expect(find.text('正在压缩…'), findsOneWidget);

    await tester.tap(find.textContaining('取消').last);
    await tester.pump();
    preparer.results.single.complete(_prepared('IMG_0001.jpg', 400000));
    await tester.pump();
    await tester.pump();

    expect(uploadBubbles(), findsNothing);
    expect(service.uploads, isEmpty);
    await finish(tester, socket);
  });

  testWidgets('"文件"入口选的图按文件原样发，不压缩', (tester) async {
    final preparer = _ControlledPreparer();
    final (_, socket, service) = await pump(
      tester,
      filePicker: () async => _photo,
      preparer: preparer,
    );

    await pickFile(tester);

    expect(preparer.calls, isEmpty);
    expect(service.uploads.single.file.size, 4000000);
    await finish(tester, socket);
  });

  testWidgets('发送栏：排进来就开始压缩并显示大小；勾"原图"按原图发，发完恢复默认',
      (tester) async {
    final preparer = _ControlledPreparer();
    final (_, socket, service) = await pump(tester, preparer: preparer);
    final DragTarget<List<PickedChatFile>> target =
        tester.widget(find.byKey(const Key('chat-drop-target')));

    target.onAcceptWithDetails!(
        DragTargetDetails(data: const [_photo], offset: Offset.zero));
    await tester.pump();

    expect(preparer.calls.single.original, isFalse, reason: '排进来就开始压缩');
    final size = find.byKey(const ValueKey('chat-pending-attachment-size-0'));
    expect(tester.widget<Text>(size).data, '压缩中');
    expect(find.text('原图 (3.8 MB)'), findsOneWidget);

    preparer.results[0].complete(_prepared('IMG_0001.jpg', 400000));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Text>(size).data, '390.6 KB');

    await tester.tap(find.byKey(const ValueKey('chat-pending-original-toggle')));
    await tester.pump();
    expect(preparer.calls.last.original, isTrue);
    expect(tester.widget<Text>(size).data, '3.8 MB', reason: '原图模式显示原图大小');
    const original = PreparedImageUpload(
      file: PickedChatFile(
        name: 'IMG_0001.jpg',
        size: 3999000,
        mimeType: 'image/jpeg',
        bytes: [7, 7, 7],
      ),
      originalSize: 4000000,
      outcome: ImagePrepareOutcome.metadataStripped,
    );
    preparer.results[1].complete(original);
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), '原图给你');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(service.uploads.single.file.bytes, [7, 7, 7], reason: '按原图（只删元数据）发');
    expect(preparer.calls, hasLength(2), reason: '已经处理好的不再重做');

    // "原图"只管刚才那一批：再拖一张进来又是压缩。
    target.onAcceptWithDetails!(
        DragTargetDetails(data: const [_photo], offset: Offset.zero));
    await tester.pump();
    expect(preparer.calls.last.original, isFalse);
    await finish(tester, socket);
  });
}
