import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/chat_upload.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../support/fake_e2ee_server.dart';

Chat _dm() => Chat(
      id: '42',
      name: 'dm',
      type: ChatType.private,
      createdAt: DateTime(2026),
    );

class _NoAuth extends AuthService {
  _NoAuth() : super.test();

  @override
  String? get accessToken => 'token';
}

/// 记下一次上传的全部内容（字段、主文件、额外文件），返回服务器会回的消息。
class _CapturingTransport {
  Map<String, String>? fields;
  List<int>? fileBytes;
  List<MultipartExtraFile> extras = const [];

  Future<http.Response> call(
    String url, {
    required Map<String, String> headers,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    List<int>? bytes,
    String? path,
    MediaType? contentType,
    List<MultipartExtraFile> extraFiles = const [],
    UploadProgressCallback? onSendProgress,
    UploadCancelToken? cancelToken,
  }) async {
    this.fields = Map.of(fields);
    fileBytes = bytes;
    extras = extraFiles;
    return http.Response.bytes(
      utf8.encode(jsonEncode({'data': serverMessage()})),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// 服务器存下来的样子：FILE + .bin + 密文信封，缩略图地址也是 .bin。
  Map<String, dynamic> serverMessage() => {
        'id': 500,
        'content': kE2eeServerPlaceholder,
        'senderId': 1,
        'chatRoomId': 42,
        'messageType': 'FILE',
        'fileUrl': '/api/files/chat/photo.bin',
        'fileName': kE2eeServerAttachmentName,
        'fileType': 'application/octet-stream',
        if (extras.isNotEmpty) 'thumbnailUrl': '/api/files/chat/thumb.bin',
        'encryptedContent': fields!['encryptedContent'],
        'encryptionVersion': kE2eeEncryptionVersion,
        'createdAt': '2026-09-25T10:00:00',
      };
}

void main() {
  late FakeE2eeServer server;
  late EncryptionService alice;
  late EncryptionService bob;

  setUp(() async {
    server = FakeE2eeServer()
      ..passwords['1'] = 'alice-pw'
      ..passwords['2'] = 'bob-pw'
      ..roomMembers['42'] = ['1', '2'];
    alice = e2eeDevice(server, '1');
    bob = e2eeDevice(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    await bob.roomState(_dm(), refresh: true);
  });

  tearDown(() => Message.contentRevealer = null);

  test(
      'compressed photo in an encrypted DM: thumbnail sealed with its own key, '
      'uploaded next to the file, and only the recipient can open it',
      () async {
    final photo = Uint8List.fromList(List.generate(4096, (i) => (i * 7) % 256));
    final thumbnail = Uint8List.fromList(
        [0xFF, 0xD8, 0xFF, ...List.generate(600, (i) => i % 256)]);
    final transport = _CapturingTransport();
    final aliceChat = ChatDataService(
      authService: _NoAuth(),
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      uploadTransport: transport.call,
      encryptionService: alice,
    );

    await aliceChat.sendFileMessage(
      '42',
      PickedChatFile(
        name: 'IMG_0001.jpg',
        size: photo.length,
        mimeType: 'image/jpeg',
        bytes: photo,
        thumbnail: () async => thumbnail,
      ),
      messageType: MessageType.image,
      chat: _dm(),
    );

    final extra = transport.extras.single;
    expect(extra.field, 'thumbnail');
    expect(extra.fileName, 'encrypted.bin');
    expect(extra.bytes, isNot(thumbnail), reason: '服务器只拿到预览图的密文');
    expect(transport.fileBytes, isNot(photo));

    final revealed = bob.reveal(Message.fromJson(transport.serverMessage()));
    expect(revealed.type, MessageType.image);
    expect(revealed.thumbnailUrl, '/api/files/chat/thumb.bin');
    expect(revealed.bubbleImageUrl, '/api/files/chat/thumb.bin');
    expect(
      await bob.openDownloadedFile(
          '/api/files/chat/thumb.bin', Uint8List.fromList(extra.bytes)),
      thumbnail,
    );
    expect(
      await bob.openDownloadedFile('/api/files/chat/photo.bin',
          Uint8List.fromList(transport.fileBytes!)),
      photo,
      reason: '点开大图照样解出原图',
    );

    // 老客户端（1.1.50）只认信封里的 file：新加的 thumb 不影响它解出原图。
    final payload =
        bob.revealResult(Message.fromJson(transport.serverMessage())).payload!;
    final legacyKey = E2eeAttachmentKey.fromJson(
        Map<String, dynamic>.from(payload.toJson()['file'] as Map));
    expect(legacyKey.name, 'IMG_0001.jpg');
    expect(payload.toJson()['thumb'], isNotNull);
  });

  test(
      'forwarding an image into an encrypted DM makes the thumbnail on the spot',
      () async {
    final transport = _CapturingTransport();
    final made = <int>[];
    final aliceChat = ChatDataService(
      authService: _NoAuth(),
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      uploadTransport: transport.call,
      encryptionService: alice,
      imageThumbnailer: (bytes) async {
        made.add(bytes.length);
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    await aliceChat.sendFileMessage(
      '42',
      PickedChatFile(
        name: 'forwarded.png',
        size: 10,
        mimeType: 'image/png',
        bytes: List.filled(10, 9),
      ),
      messageType: MessageType.image,
      chat: _dm(),
    );

    expect(made, [10]);
    expect(transport.extras, hasLength(1));
  });

  test(
      'messages whose envelope has no thumbnail key never use the thumbnail url '
      '(sent by an old client, or a url the server made up)', () async {
    final sealed = await alice.sealFile(
      _dm(),
      name: 'old.jpg',
      mimeType: 'image/jpeg',
      kind: 'image',
      readBytes: () async => Uint8List(100),
    );
    final message = Message.fromJson({
      'id': '600',
      'content': kE2eeServerPlaceholder,
      'senderId': '1',
      'chatRoomId': '42',
      'type': 'FILE',
      'fileUrl': '/api/files/chat/old.bin',
      'thumbnailUrl': '/api/files/chat/injected.bin',
      'encryptedContent': sealed!.envelope,
      'encryptionVersion': kE2eeEncryptionVersion,
      'createdAt': '2026-09-25T10:00:00',
    });

    final revealed = bob.reveal(message);

    expect(revealed.thumbnailUrl, isNull);
    expect(revealed.bubbleImageUrl, '/api/files/chat/old.bin');
    expect(sealed.thumbnailCiphertext, isNull);
  });

  test('plaintext chats never upload a client thumbnail (the server makes one)',
      () async {
    final transport = _CapturingTransport();
    var asked = false;
    final chat = ChatDataService(
      authService: _NoAuth(),
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      uploadTransport: (url,
          {required headers,
          required fields,
          required fileField,
          required fileName,
          bytes,
          path,
          contentType,
          extraFiles = const [],
          onSendProgress,
          cancelToken}) async {
        transport.extras = extraFiles;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'data': {
              'id': 1,
              'content': 'a.jpg',
              'senderId': 1,
              'chatRoomId': 7
            },
          })),
          200,
        );
      },
      encryptionService: alice,
    );

    await chat.sendFileMessage(
      '7',
      PickedChatFile(
        name: 'a.jpg',
        size: 3,
        mimeType: 'image/jpeg',
        bytes: const [1, 2, 3],
        thumbnail: () async {
          asked = true;
          return Uint8List(1);
        },
      ),
      messageType: MessageType.image,
    );

    expect(asked, isFalse);
    expect(transport.extras, isEmpty);
  });
}
