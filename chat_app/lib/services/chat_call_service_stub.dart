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
    final action = signal['action']?.toString();
    if (action == 'invite') {
      final peerId = _asInt(signal['fromUserId']);
      _state = ChatCallState(
        phase: CallPhase.incoming,
        callId: signal['callId']?.toString(),
        chatRoomId: _asInt(signal['chatRoomId']),
        mediaKind: CallMediaKind.fromWire(signal['mediaType']),
        participants: [
          if (peerId != null)
            CallParticipant(
              userId: peerId,
              displayName: signal['fromName']?.toString() ?? '联系人',
            ),
        ],
        errorMessage: '当前平台暂不支持浏览器实时通话',
      );
      notifyListeners();
    } else if ((action == 'hangup' || action == 'reject') &&
        signal['callId']?.toString() == _state.callId) {
      _state = ChatCallState(
        phase: CallPhase.ended,
        mediaKind: _state.mediaKind,
        errorMessage: action == 'reject' ? '对方已拒绝通话' : '通话已结束',
      );
      notifyListeners();
    }
  }

  Future<void> startOutgoingCall({
    required int chatRoomId,
    required CallMediaKind mediaKind,
    required String peerName,
    int? peerUserId,
  }) async {
    throw UnsupportedError('当前平台暂不支持浏览器实时通话');
  }

  Future<void> acceptIncoming() async {
    _webSocketService.sendCallSignal({
      'action': 'reject',
      'chatRoomId': state.chatRoomId,
      'callId': state.callId,
      'toUserId': state.others.isNotEmpty ? state.others.first.userId : null,
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
      'toUserId': state.others.isNotEmpty ? state.others.first.userId : null,
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
