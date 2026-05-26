enum CallMediaKind {
  audio('语音'),
  video('视频');

  const CallMediaKind(this.label);

  final String label;

  String get wireName => this == CallMediaKind.video ? 'VIDEO' : 'AUDIO';

  static CallMediaKind fromWire(dynamic value) {
    return value?.toString().toUpperCase() == 'VIDEO'
        ? CallMediaKind.video
        : CallMediaKind.audio;
  }
}

enum CallPhase {
  idle,
  incoming,
  outgoing,
  connecting,
  connected,
  ended,
  failed,
}

class ChatCallState {
  const ChatCallState({
    this.phase = CallPhase.idle,
    this.callId,
    this.chatRoomId,
    this.peerUserId,
    this.peerName,
    this.mediaKind = CallMediaKind.audio,
    this.localViewId,
    this.remoteViewId,
    this.microphoneMuted = false,
    this.cameraOff = false,
    this.errorMessage,
  });

  final CallPhase phase;
  final String? callId;
  final int? chatRoomId;
  final int? peerUserId;
  final String? peerName;
  final CallMediaKind mediaKind;
  final String? localViewId;
  final String? remoteViewId;
  final bool microphoneMuted;
  final bool cameraOff;
  final String? errorMessage;

  bool get isIdle => phase == CallPhase.idle;
  bool get isActive =>
      phase == CallPhase.incoming ||
      phase == CallPhase.outgoing ||
      phase == CallPhase.connecting ||
      phase == CallPhase.connected;
  bool get hasRemoteMedia => remoteViewId != null && remoteViewId!.isNotEmpty;
  bool get isVideo => mediaKind == CallMediaKind.video;

  String get statusLabel {
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return errorMessage!;
    }
    return switch (phase) {
      CallPhase.idle => '未通话',
      CallPhase.incoming => '来电',
      CallPhase.outgoing => '正在呼叫',
      CallPhase.connecting => '正在连接',
      CallPhase.connected => '通话中',
      CallPhase.ended => '通话已结束',
      CallPhase.failed => '通话失败',
    };
  }

  ChatCallState copyWith({
    CallPhase? phase,
    String? callId,
    int? chatRoomId,
    int? peerUserId,
    String? peerName,
    CallMediaKind? mediaKind,
    String? localViewId,
    String? remoteViewId,
    bool? microphoneMuted,
    bool? cameraOff,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatCallState(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      peerUserId: peerUserId ?? this.peerUserId,
      peerName: peerName ?? this.peerName,
      mediaKind: mediaKind ?? this.mediaKind,
      localViewId: localViewId ?? this.localViewId,
      remoteViewId: remoteViewId ?? this.remoteViewId,
      microphoneMuted: microphoneMuted ?? this.microphoneMuted,
      cameraOff: cameraOff ?? this.cameraOff,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
