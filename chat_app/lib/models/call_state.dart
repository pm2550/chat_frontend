const int kCallMeshParticipantLimit = 6;

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
  ringing,
  connecting,
  connected,
  declined,
  timeout,
  ended,
  failed,
}

enum PeerConnectionState {
  connecting,
  connected,
  disconnected,
  failed,
}

class CallParticipant {
  const CallParticipant({
    required this.userId,
    required this.displayName,
    this.anonymous = false,
    this.anonymousTheme,
    this.localViewId,
    this.remoteViewId,
    this.micMuted = false,
    this.cameraOff = false,
    this.state = PeerConnectionState.connecting,
  });

  final int userId;
  final String displayName;
  final bool anonymous;
  final String? anonymousTheme;
  final String? localViewId;
  final String? remoteViewId;
  final bool micMuted;
  final bool cameraOff;
  final PeerConnectionState state;

  bool get isConnected => state == PeerConnectionState.connected;
  bool get hasVideo => (localViewId ?? remoteViewId)?.isNotEmpty == true;

  CallParticipant copyWith({
    int? userId,
    String? displayName,
    bool? anonymous,
    String? anonymousTheme,
    String? localViewId,
    String? remoteViewId,
    bool? micMuted,
    bool? cameraOff,
    PeerConnectionState? state,
    bool clearAnonymousTheme = false,
    bool clearLocalView = false,
    bool clearRemoteView = false,
  }) {
    return CallParticipant(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      anonymous: anonymous ?? this.anonymous,
      anonymousTheme:
          clearAnonymousTheme ? null : anonymousTheme ?? this.anonymousTheme,
      localViewId: clearLocalView ? null : localViewId ?? this.localViewId,
      remoteViewId: clearRemoteView ? null : remoteViewId ?? this.remoteViewId,
      micMuted: micMuted ?? this.micMuted,
      cameraOff: cameraOff ?? this.cameraOff,
      state: state ?? this.state,
    );
  }
}

class ChatCallState {
  const ChatCallState({
    this.phase = CallPhase.idle,
    this.callId,
    this.chatRoomId,
    this.mediaKind = CallMediaKind.audio,
    this.participants = const [],
    this.selfUserId,
    this.errorMessage,
  });

  final CallPhase phase;
  final String? callId;
  final int? chatRoomId;
  final CallMediaKind mediaKind;
  final List<CallParticipant> participants;
  final int? selfUserId;
  final String? errorMessage;

  bool get isIdle => phase == CallPhase.idle;
  bool get isActive =>
      phase == CallPhase.incoming ||
      phase == CallPhase.outgoing ||
      phase == CallPhase.ringing ||
      phase == CallPhase.connecting ||
      phase == CallPhase.connected;
  bool get isVideo => mediaKind == CallMediaKind.video;
  bool get isFull => participants.length >= kCallMeshParticipantLimit;
  bool get hasRemoteMedia => others.any((participant) =>
      participant.remoteViewId != null && participant.remoteViewId!.isNotEmpty);

  CallParticipant? get self {
    final id = selfUserId;
    if (id == null) return null;
    for (final participant in participants) {
      if (participant.userId == id) {
        return participant;
      }
    }
    return null;
  }

  List<CallParticipant> get others {
    final id = selfUserId;
    if (id == null) return participants;
    return participants
        .where((participant) => participant.userId != id)
        .toList(growable: false);
  }

  String get statusLabel {
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return errorMessage!;
    }
    return switch (phase) {
      CallPhase.idle => '未通话',
      CallPhase.incoming => '来电',
      CallPhase.outgoing => '正在呼叫',
      CallPhase.ringing => '等待对方接听',
      CallPhase.connecting => '正在连接',
      CallPhase.connected => '通话中',
      CallPhase.declined => '对方已拒绝通话',
      CallPhase.timeout => '对方未应答',
      CallPhase.ended => '通话已结束',
      CallPhase.failed => '通话失败',
    };
  }

  String get primaryPeerName {
    final peer = others.isNotEmpty ? others.first : null;
    return peer?.displayName ?? '联系人';
  }

  ChatCallState addParticipant(CallParticipant participant) {
    final next = [
      for (final existing in participants)
        if (existing.userId != participant.userId) existing,
      participant,
    ]..sort((a, b) => a.userId.compareTo(b.userId));
    return copyWith(participants: next);
  }

  ChatCallState removeParticipant(int userId) {
    return copyWith(
      participants: participants
          .where((participant) => participant.userId != userId)
          .toList(growable: false),
    );
  }

  ChatCallState updateParticipant(
    int userId,
    CallParticipant Function(CallParticipant participant) transform,
  ) {
    var changed = false;
    final next = [
      for (final participant in participants)
        if (participant.userId == userId)
          () {
            changed = true;
            return transform(participant);
          }()
        else
          participant,
    ];
    return changed ? copyWith(participants: next) : this;
  }

  ChatCallState copyWith({
    CallPhase? phase,
    String? callId,
    int? chatRoomId,
    CallMediaKind? mediaKind,
    List<CallParticipant>? participants,
    int? selfUserId,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatCallState(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      mediaKind: mediaKind ?? this.mediaKind,
      participants:
          List<CallParticipant>.unmodifiable(participants ?? this.participants),
      selfUserId: selfUserId ?? this.selfUserId,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
