import 'dart:async';

import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/agent_client_tools.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AgentClientToolState state;
  late AgentClientToolRegistry registry;

  setUp(() {
    state = AgentClientToolState()..resetForTesting();
    registry = AgentClientToolRegistry()..clearForTesting();
  });

  tearDown(() {
    state.resetForTesting();
    registry.clearForTesting();
  });

  test('registry registers and looks up tools by name', () {
    final tool = GetOpenChatPanelsTool(state);

    registry.register(tool);

    expect(registry.getByName('get_open_chat_panels'), same(tool));
    expect(registry.getByName('missing'), isNull);
  });

  test('get_local_room_settings reads current local state', () async {
    state.updateRoom(
      roomId: 42,
      muted: true,
      pinnedToTop: true,
      notificationLevel: 'mentions',
      customNickname: '项目房间',
    );

    final result = await GetLocalRoomSettingsTool(state).execute({});

    expect(result['muted'], isTrue);
    expect(result['pinnedToTop'], isTrue);
    expect(result['notificationLevel'], 'mentions');
    expect(result['customNickname'], '项目房间');
  });

  test('get_open_chat_panels reads current UI state', () async {
    state.updateRoom(
      roomId: 42,
      muted: false,
      pinnedToTop: false,
      rightSidebarOpen: true,
      rightSidebarTab: 'files',
      membersPanelOpen: false,
      settingsOpen: true,
    );

    final result = await GetOpenChatPanelsTool(state).execute({});

    expect(result['currentRoomId'], 42);
    expect(result['rightSidebarOpen'], isTrue);
    expect(result['rightSidebarTab'], 'files');
    expect(result['membersPanelOpen'], isFalse);
    expect(result['settingsOpen'], isTrue);
  });

  test('get_recent_attachments returns cached attachment metadata', () async {
    state.updateRoom(
      roomId: 42,
      muted: false,
      pinnedToTop: false,
      messages: [
        message('1', type: MessageType.text),
        message(
          '2',
          type: MessageType.image,
          fileUrl: '/api/files/chat/a.png',
          fileName: 'a.png',
          fileType: 'image/png',
        ),
      ],
    );

    final result =
        await GetRecentAttachmentsTool(state).execute({'roomId': 42, 'n': 20});
    final attachments = result['attachments'] as List;

    expect(attachments, hasLength(1));
    expect(attachments.single['messageId'], 2);
    expect(attachments.single['filename'], 'a.png');
    expect(attachments.single['mimeType'], 'image/png');
  });

  testWidgets('prompt_user_confirmation shows PM dialog and answers yes',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    state.navigatorKey = navigatorKey;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('host')),
    ));

    final future = PromptUserConfirmationTool(state).execute({
      'question': '确认继续吗？',
      'yes_label': '是',
      'no_label': '否',
    });
    await tester.pump();

    expect(find.text('Agent 请求确认'), findsOneWidget);
    expect(find.text('确认继续吗？'), findsOneWidget);
    await tester.tap(find.text('是'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result['answered'], 'yes');
  });

  test('read_clipboard returns text from clipboard reader', () async {
    state.clipboardReader = (_) async => const ClipboardData(text: 'hello');

    final result = await ReadClipboardTool(state).execute({});

    expect(result['text'], 'hello');
  });

  test('read_clipboard returns permission error honestly', () async {
    state.clipboardReader = (_) async => throw PlatformException(
          code: 'denied',
          message: 'permission denied',
        );

    final result = await ReadClipboardTool(state).execute({});

    expect(result['error']['code'], 'permission_denied');
  });

  test('websocket service builds result payload for registered client tool',
      () async {
    registry.register(GetOpenChatPanelsTool(state));
    state.updateRoom(roomId: 42, muted: false, pinnedToTop: false);
    final service = WebSocketService()
      ..setAgentClientToolRegistryForTesting(registry);

    final payload = await service.buildAgentToolResultForTest({
      'type': 'agent_tool_request',
      'callId': 'call-1',
      'toolName': 'get_open_chat_panels',
      'params': {},
    });

    expect(payload?['type'], 'agent_tool_result');
    expect(payload?['callId'], 'call-1');
    expect(payload?['result']['currentRoomId'], 42);
  });

  test('websocket service reports unregistered tool error', () async {
    final service = WebSocketService()
      ..setAgentClientToolRegistryForTesting(registry);

    final payload = await service.buildAgentToolResultForTest({
      'type': 'agent_tool_request',
      'callId': 'call-2',
      'toolName': 'missing_tool',
      'params': {},
    });

    expect(payload?['error']['code'], 'tool_not_registered');
  });

  test('websocket service refreshes access token before reconnecting',
      () async {
    final authService = _RefreshingAuthService();
    final service = WebSocketService.forTesting(authService: authService);

    await service.connect();

    expect(authService.ensureAuthenticatedCalls, 1);
    expect(authService.refreshAccessTokenCalls, 1);
    expect(service.isConnected, isFalse);
  });

  test('concurrent websocket connect calls share one authentication flight',
      () async {
    final authService = _BlockingAuthService();
    final service = WebSocketService.forTesting(authService: authService);

    final first = service.connect();
    final second = service.connect();
    await Future<void>.delayed(Duration.zero);

    expect(authService.ensureAuthenticatedCalls, 1);
    authService.release();
    await Future.wait([first, second]);
    expect(authService.refreshAccessTokenCalls, 1);
    expect(service.isConnected, isFalse);
  });
}

class _BlockingAuthService extends AuthService {
  _BlockingAuthService() : super.test();

  final Completer<void> _gate = Completer<void>();
  int ensureAuthenticatedCalls = 0;
  int refreshAccessTokenCalls = 0;
  String? _token = 'temporary-token';

  void release() => _gate.complete();

  @override
  String? get accessToken => _token;

  @override
  Future<bool> ensureAuthenticated() async {
    ensureAuthenticatedCalls += 1;
    await _gate.future;
    return true;
  }

  @override
  Future<bool> refreshAccessToken() async {
    refreshAccessTokenCalls += 1;
    _token = null;
    return false;
  }
}

class _RefreshingAuthService extends AuthService {
  _RefreshingAuthService() : super.test();

  int ensureAuthenticatedCalls = 0;
  int refreshAccessTokenCalls = 0;
  String? _token = 'stale-access-token';

  @override
  String? get accessToken => _token;

  @override
  Future<bool> ensureAuthenticated() async {
    ensureAuthenticatedCalls++;
    return true;
  }

  @override
  Future<bool> refreshAccessToken() async {
    refreshAccessTokenCalls++;
    _token = null;
    return false;
  }
}

Message message(
  String id, {
  MessageType type = MessageType.text,
  String? fileUrl,
  String? fileName,
  String? fileType,
}) {
  return Message(
    id: id,
    content: 'content $id',
    senderId: '7',
    senderName: 'Alice',
    chatRoomId: '42',
    timestamp: DateTime.parse('2026-06-01T00:00:0$id'),
    type: type,
    status: MessageStatus.sent,
    fileUrl: fileUrl,
    fileName: fileName,
    fileType: fileType,
  );
}
