import 'package:flutter/foundation.dart';

import '../models/call_state.dart';
import 'auth_service.dart';
import 'websocket_service.dart';

class ChatCallService extends ChangeNotifier {
  ChatCallService({
    required WebSocketService webSocketService,
    AuthService? authService,
  }) : _webSocketService = webSocketService;

  final WebSocketService _webSocketService;

  ChatCallState _state = const ChatCallState();
  ChatCallState get state => _state;
  bool get isSupported => false;

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    if (signal['action']?.toString() == 'invite') {
      _state = ChatCallState(
        phase: CallPhase.incoming,
        callId: signal['callId']?.toString(),
        chatRoomId: _asInt(signal['chatRoomId']),
        peerUserId: _asInt(signal['fromUserId']),
        peerName: signal['fromName']?.toString(),
        mediaKind: CallMediaKind.fromWire(signal['mediaType']),
        errorMessage: '当前平台暂不支持浏览器实时通话',
      );
      notifyListeners();
    }
  }

  Future<void> startOutgoingCall({
    required int chatRoomId,
    required CallMediaKind mediaKind,
    required String peerName,
  }) async {
    throw UnsupportedError('当前平台暂不支持浏览器实时通话');
  }

  Future<void> acceptIncoming() async {
    _webSocketService.sendCallSignal({
      'action': 'reject',
      'chatRoomId': state.chatRoomId,
      'callId': state.callId,
      'toUserId': state.peerUserId,
      'mediaType': state.mediaKind.wireName,
    });
    _state = const ChatCallState(
      phase: CallPhase.failed,
      errorMessage: '当前平台暂不支持浏览器实时通话',
    );
    notifyListeners();
  }

  void rejectIncoming() {
    _webSocketService.sendCallSignal({
      'action': 'reject',
      'chatRoomId': state.chatRoomId,
      'callId': state.callId,
      'toUserId': state.peerUserId,
      'mediaType': state.mediaKind.wireName,
    });
    clear();
  }

  Future<void> hangUp() async {
    clear();
  }

  void toggleMicrophone() {}
  void toggleCamera() {}

  void clear() {
    _state = const ChatCallState();
    notifyListeners();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
