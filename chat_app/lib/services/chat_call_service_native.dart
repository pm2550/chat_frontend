import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../constants/api_constants.dart';
import '../models/call_state.dart';
import 'active_call_tracker.dart';
import 'auth_service.dart';
import 'call_ice_config.dart';
import 'call_media_registry_native.dart';
import 'call_mesh_policy.dart';
import 'websocket_service.dart';

/// 原生端（Android/iOS/桌面）的实时通话，基于 flutter_webrtc。
///
/// 信令协议、状态机与网页版 chat_call_service_web.dart 完全一致，两端可以互通；
/// 区别只在 WebRTC 实现和画面渲染（见 CallMediaRegistry）。
class ChatCallService extends ChangeNotifier {
  ChatCallService({
    required WebSocketService webSocketService,
    AuthService? authService,
  })  : _webSocketService = webSocketService,
        _authService = authService ?? AuthService();

  final WebSocketService _webSocketService;
  final AuthService _authService;
  final Random _random = Random();

  ChatCallState _state = const ChatCallState();
  ChatCallState get state => _state;
  bool get isSupported => true;

  final Map<int, _PeerSession> _peers = {};

  /// 对方的 ICE 候选常比我们建好连接、设好远端描述更早到；先排队，设完远端描述再补。
  /// 丢掉的话，需要 TURN 中继的通话（两边都在运营商 NAT 后面）一定接不通。
  final Map<int, List<RTCIceCandidate>> _pendingIce = {};
  static const int _maxPendingIcePerPeer = 64;
  final Map<int, Future<_PeerSession>> _pendingPeerSessions = {};
  MediaStream? _localStream;
  String? _localViewId;
  Timer? _iceConfigRefreshTimer;
  Timer? _outgoingTimeoutTimer;
  CallIceConfig? _cachedIceConfig;
  bool _disposed = false;

  Future<void> startOutgoingCall({
    required int chatRoomId,
    required CallMediaKind mediaKind,
    required String peerName,
    int? peerUserId,
  }) async {
    if (_state.isActive) {
      await hangUp(sendSignal: true);
    }

    final selfUserId = _currentUserId();
    if (selfUserId == null) {
      _fail('无法识别当前用户，不能发起通话');
      return;
    }

    final callId = _newCallId();
    _setState(ChatCallState(
      phase: CallPhase.outgoing,
      callId: callId,
      chatRoomId: chatRoomId,
      mediaKind: mediaKind,
      selfUserId: selfUserId,
      participants: [
        CallParticipant(
          userId: selfUserId,
          displayName: _selfDisplayName(),
          state: PeerConnectionState.connected,
        ),
      ],
    ));

    try {
      await _ensureLocalMedia(mediaKind);
      _sendJoin();
      _sendSignal({
        'action': 'invite',
        'chatRoomId': chatRoomId,
        'callId': callId,
        if (peerUserId != null) 'toUserId': peerUserId,
        'mediaType': mediaKind.wireName,
      });
      _startOutgoingTimeout(callId);
    } catch (error) {
      _fail('无法启动${mediaKind.label}通话: $error');
    }
  }

  Future<void> joinExistingCall(
    String callId,
    int chatRoomId, {
    CallMediaKind mediaKind = CallMediaKind.audio,
  }) async {
    if (_state.isFull) {
      _fail('通话已满 $kCallMeshParticipantLimit/$kCallMeshParticipantLimit');
      return;
    }
    final selfUserId = _currentUserId();
    if (selfUserId == null) {
      _fail('无法识别当前用户，不能加入通话');
      return;
    }
    if (!_state.isActive || _state.callId != callId) {
      _setState(ChatCallState(
        phase: CallPhase.connecting,
        callId: callId,
        chatRoomId: chatRoomId,
        mediaKind: mediaKind,
        selfUserId: selfUserId,
        participants: [
          CallParticipant(
            userId: selfUserId,
            displayName: _selfDisplayName(),
            state: PeerConnectionState.connected,
          ),
        ],
      ));
    }
    try {
      await _ensureLocalMedia(_state.mediaKind);
      _sendJoin();
    } catch (error) {
      _fail('无法加入${mediaKind.label}通话: $error');
    }
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    final action = signal['action']?.toString();
    final fromUserId = _asInt(signal['fromUserId']);
    final toUserId = _asInt(signal['toUserId']);
    final selfUserId = _currentUserId();
    if (isOwnCallSignalEcho(
      action: action,
      fromUserId: fromUserId,
      selfUserId: selfUserId,
    )) {
      return;
    }
    if (toUserId != null && selfUserId != null && toUserId != selfUserId) {
      return;
    }

    switch (action) {
      case 'invite':
        _receiveInvite(signal);
      case 'call_ringing':
        _handleCallRinging(signal);
      case 'join_accepted':
        await _handleJoinAccepted(signal);
      case 'participant_joined':
        await _handleParticipantJoined(signal);
      case 'participant_left':
        _handleParticipantLeft(signal);
      case 'error':
        _handleCallError(signal);
      case 'accept':
        await _handleAccept(signal);
      case 'reject':
        _endRemote('对方已拒绝通话', phase: CallPhase.declined);
      case 'offer':
        await _handleOffer(signal);
      case 'answer':
        await _handleAnswer(signal);
      case 'ice':
        await _handleIce(signal);
      case 'hangup':
        _handleParticipantLeft(signal);
    }
  }

  Future<void> acceptIncoming() async {
    if (_state.phase != CallPhase.incoming ||
        _state.chatRoomId == null ||
        _state.callId == null) {
      return;
    }
    final selfUserId = _currentUserId();
    if (selfUserId == null) {
      _fail('无法识别当前用户，不能接听通话');
      return;
    }
    try {
      _setState(_state
          .addParticipant(CallParticipant(
            userId: selfUserId,
            displayName: _selfDisplayName(),
            state: PeerConnectionState.connected,
          ))
          .copyWith(
            selfUserId: selfUserId,
            phase: CallPhase.connecting,
            clearError: true,
          ));
      await _ensureLocalMedia(_state.mediaKind);
      _sendJoin();
    } catch (error) {
      final inviter = _state.others.isNotEmpty ? _state.others.first : null;
      _sendSignal({
        'action': 'reject',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        if (inviter != null) 'toUserId': inviter.userId,
        'mediaType': _state.mediaKind.wireName,
      });
      _fail('无法接听${_state.mediaKind.label}通话: $error');
    }
  }

  void rejectIncoming() {
    if (_state.phase == CallPhase.incoming) {
      final inviter = _state.others.isNotEmpty ? _state.others.first : null;
      _sendSignal({
        'action': 'reject',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        if (inviter != null) 'toUserId': inviter.userId,
        'mediaType': _state.mediaKind.wireName,
      });
    }
    clear();
  }

  Future<void> hangUp({bool sendSignal = true}) async {
    if (sendSignal && _state.isActive) {
      _sendSignal({
        'action': 'leave',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'mediaType': _state.mediaKind.wireName,
      });
      _sendSignal({
        'action': 'hangup',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'mediaType': _state.mediaKind.wireName,
      });
    }
    _disposeAllPeers();
    _stopLocalMedia();
    _setState(ChatCallState(
      phase: CallPhase.ended,
      mediaKind: _state.mediaKind,
      selfUserId: _state.selfUserId,
    ));
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (_state.phase == CallPhase.ended) clear();
    });
  }

  void toggleMicrophone() {
    final muted = !(_state.self?.micMuted ?? false);
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
    final selfUserId = _state.selfUserId;
    if (selfUserId != null) {
      _setState(_state.updateParticipant(
        selfUserId,
        (participant) => participant.copyWith(micMuted: muted),
      ));
    }
  }

  void toggleCamera() {
    final off = !(_state.self?.cameraOff ?? false);
    for (final track in _localStream?.getVideoTracks() ?? const []) {
      track.enabled = !off;
    }
    final selfUserId = _state.selfUserId;
    if (selfUserId != null) {
      _setState(_state.updateParticipant(
        selfUserId,
        (participant) => participant.copyWith(cameraOff: off),
      ));
    }
  }

  void clear() {
    _disposeAllPeers();
    _stopLocalMedia();
    _setState(const ChatCallState());
  }

  void _receiveInvite(Map<String, dynamic> signal) {
    final callerUserId = _asInt(signal['fromUserId']);
    if (callerUserId == null) return;
    if (_state.isActive) {
      if (_state.callId == signal['callId']?.toString()) return;
      _sendSignal({
        'action': 'reject',
        'chatRoomId': _asInt(signal['chatRoomId']),
        'callId': signal['callId']?.toString(),
        'toUserId': callerUserId,
        'mediaType': CallMediaKind.fromWire(signal['mediaType']).wireName,
      });
      return;
    }
    _setState(ChatCallState(
      phase: CallPhase.incoming,
      callId: signal['callId']?.toString(),
      chatRoomId: _asInt(signal['chatRoomId']),
      mediaKind: CallMediaKind.fromWire(signal['mediaType']),
      selfUserId: _currentUserId(),
      participants: [
        CallParticipant(
          userId: callerUserId,
          displayName: _participantName(signal, fallback: '联系人'),
        ),
      ],
    ));
  }

  Future<void> _handleJoinAccepted(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    final selfUserId = _state.selfUserId ?? _currentUserId();
    if (selfUserId == null) return;
    final existingParticipantIds = _intList(signal['existingParticipantIds'])
        .where((id) => id != selfUserId)
        .toList(growable: false);
    final nextPhase =
        existingParticipantIds.isEmpty ? _state.phase : CallPhase.connecting;
    _setState(_state.copyWith(
      phase: nextPhase,
      selfUserId: selfUserId,
      clearError: true,
    ));
    for (final peerUserId in existingParticipantIds) {
      await _ensurePeerSession(
        peerUserId,
        peerName: _knownParticipantName(peerUserId),
        isOfferer: shouldCreateMeshOffer(
          selfUserId: selfUserId,
          peerUserId: peerUserId,
        ),
      );
    }
  }

  Future<void> _handleParticipantJoined(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    if (_state.phase == CallPhase.incoming) return;
    final peerUserId = _asInt(signal['userId'] ?? signal['fromUserId']);
    final selfUserId = _state.selfUserId ?? _currentUserId();
    if (peerUserId == null || selfUserId == null || peerUserId == selfUserId) {
      return;
    }
    _outgoingTimeoutTimer?.cancel();
    if (_state.phase != CallPhase.connected) {
      _setState(_state.copyWith(phase: CallPhase.connecting, clearError: true));
    }
    await _ensurePeerSession(
      peerUserId,
      peerName: _participantName(signal, fallback: '成员 $peerUserId'),
      isOfferer: shouldCreateMeshOffer(
        selfUserId: selfUserId,
        peerUserId: peerUserId,
      ),
    );
  }

  void _handleParticipantLeft(Map<String, dynamic> signal) {
    if (!_isCurrentCall(signal)) return;
    final peerUserId = _asInt(signal['userId'] ?? signal['fromUserId']);
    if (peerUserId == null) return;
    if (_state.phase == CallPhase.incoming) {
      // 还没接听对方就挂了。以前这里只移除了对方、状态却停在"来电中"（仍算通话中），
      // 下一通来电会被当成占线自动拒掉。
      _endRemote('对方已取消通话');
      return;
    }
    _disposePeerSession(peerUserId);
    final next = _state.removeParticipant(peerUserId);
    _setState(next.others.isEmpty && next.self != null
        ? next.copyWith(phase: CallPhase.ended)
        : next);
  }

  void _handleCallError(Map<String, dynamic> signal) {
    if (!_isCurrentCall(signal)) return;
    final error = signal['error']?.toString();
    if (error == 'ROOM_FULL') {
      _fail('通话已满 ${signal['current'] ?? kCallMeshParticipantLimit}/'
          '${signal['max'] ?? kCallMeshParticipantLimit}');
      return;
    }
    _fail(error == null || error.isEmpty ? '通话信令失败' : error);
  }

  Future<void> _handleAccept(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    final peerUserId = _asInt(signal['fromUserId']);
    final selfUserId = _state.selfUserId ?? _currentUserId();
    if (peerUserId == null || selfUserId == null) return;
    _outgoingTimeoutTimer?.cancel();
    if (_state.phase != CallPhase.connected) {
      _setState(_state.copyWith(phase: CallPhase.connecting, clearError: true));
    }
    await _ensurePeerSession(
      peerUserId,
      peerName: _participantName(signal, fallback: '联系人'),
      isOfferer: shouldCreateMeshOffer(
        selfUserId: selfUserId,
        peerUserId: peerUserId,
      ),
    );
  }

  Future<void> _handleOffer(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    if (_state.phase == CallPhase.incoming) return;
    final fromUserId = _asInt(signal['fromUserId']);
    if (fromUserId == null) return;

    final session = await _ensurePeerSession(
      fromUserId,
      peerName: _participantName(signal, fallback: '联系人'),
      isOfferer: false,
    );
    await session.pc.setRemoteDescription(RTCSessionDescription(
      signal['sdp']?.toString() ?? '',
      signal['sdpType']?.toString() ?? 'offer',
    ));
    session.remoteDescriptionSet = true;
    await _flushPendingIce(fromUserId, session);
    final answer = await session.pc.createAnswer();
    await session.pc.setLocalDescription(answer);
    _sendSignal({
      'action': 'answer',
      'chatRoomId': _state.chatRoomId,
      'callId': _state.callId,
      'toUserId': fromUserId,
      'mediaType': _state.mediaKind.wireName,
      'sdpType': answer.type,
      'sdp': answer.sdp,
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    final fromUserId = _asInt(signal['fromUserId']);
    if (fromUserId == null) return;
    final session = _peers[fromUserId];
    if (session == null) return;
    await session.pc.setRemoteDescription(RTCSessionDescription(
      signal['sdp']?.toString() ?? '',
      signal['sdpType']?.toString() ?? 'answer',
    ));
    session.remoteDescriptionSet = true;
    await _flushPendingIce(fromUserId, session);
    _markPeerState(fromUserId, PeerConnectionState.connected);
  }

  Future<void> _handleIce(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    final fromUserId = _asInt(signal['fromUserId']);
    if (fromUserId == null) return;
    final rawCandidate = signal['candidate'];
    if (rawCandidate is! Map) return;
    final candidate = rawCandidate['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) return;
    final ice = RTCIceCandidate(
      candidate,
      rawCandidate['sdpMid']?.toString(),
      _asInt(rawCandidate['sdpMLineIndex']),
    );
    final session = _peers[fromUserId];
    if (session == null || !session.remoteDescriptionSet) {
      final queue = _pendingIce.putIfAbsent(fromUserId, () => []);
      if (queue.length < _maxPendingIcePerPeer) queue.add(ice);
      return;
    }
    await _addIceCandidate(session, ice);
  }

  Future<void> _flushPendingIce(int peerUserId, _PeerSession session) async {
    final queued = _pendingIce.remove(peerUserId);
    if (queued == null) return;
    for (final ice in queued) {
      await _addIceCandidate(session, ice);
    }
  }

  Future<void> _addIceCandidate(_PeerSession session, RTCIceCandidate ice) async {
    try {
      await session.pc.addCandidate(ice);
    } catch (_) {
      // 单个候选无效（对方网卡已下线等）不影响其余候选和通话本身。
    }
  }

  Future<void> _ensureLocalMedia(CallMediaKind mediaKind) async {
    if (_localStream != null) {
      _registerSelfParticipant(mediaKind);
      return;
    }
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': mediaKind == CallMediaKind.video
          ? {'facingMode': 'user'}
          : false,
    });
    _localStream = stream;
    if (mediaKind == CallMediaKind.video) {
      final viewId = _newViewId('local');
      await CallMediaRegistry.register(viewId, stream, mirror: true);
      _localViewId = viewId;
    }
    // 视频通话默认外放，语音通话走听筒（和普通打电话一致）。
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(Helper.setSpeakerphoneOn(mediaKind == CallMediaKind.video)
          .catchError((_) {}));
    }
    _registerSelfParticipant(mediaKind);
  }

  Future<_PeerSession> _ensurePeerSession(
    int peerUserId, {
    required String peerName,
    required bool isOfferer,
  }) async {
    final existing = _peers[peerUserId];
    if (existing != null) {
      _setState(_state.addParticipant(CallParticipant(
        userId: peerUserId,
        displayName: peerName,
        remoteViewId: existing.remoteViewId,
        state: existing.participantState,
      )));
      return existing;
    }
    final pending = _pendingPeerSessions[peerUserId];
    if (pending != null) {
      final session = await pending;
      _setState(_state.addParticipant(CallParticipant(
        userId: peerUserId,
        displayName: peerName,
        remoteViewId: session.remoteViewId,
        state: session.participantState,
      )));
      return session;
    }
    final future = _createPeerSession(
      peerUserId,
      peerName: peerName,
      isOfferer: isOfferer,
    );
    _pendingPeerSessions[peerUserId] = future;
    try {
      return await future;
    } finally {
      _pendingPeerSessions.remove(peerUserId);
    }
  }

  Future<_PeerSession> _createPeerSession(
    int peerUserId, {
    required String peerName,
    required bool isOfferer,
  }) async {
    await _ensureLocalMedia(_state.mediaKind);
    final iceConfig = await _loadIceConfig();
    final pc = await createPeerConnection({
      'iceServers': [
        for (final server in iceConfig.iceServers)
          {
            'urls': server.urls,
            if (server.username != null) 'username': server.username,
            if (server.credential != null) 'credential': server.credential,
          },
      ],
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
    });
    final local = _localStream!;
    for (final track in local.getTracks()) {
      await pc.addTrack(track, local);
    }

    final session = _PeerSession(peerUserId: peerUserId, pc: pc);
    _peers[peerUserId] = session;
    _setState(_state.addParticipant(CallParticipant(
      userId: peerUserId,
      displayName: peerName,
      state: PeerConnectionState.connecting,
    )));

    pc.onIceCandidate = (candidate) {
      final text = candidate.candidate;
      if (text == null || text.isEmpty || _state.chatRoomId == null) return;
      _sendSignal({
        'action': 'ice',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'toUserId': peerUserId,
        'mediaType': _state.mediaKind.wireName,
        'candidate': {
          'candidate': text,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      final stream = event.streams.first;
      if (identical(session.remoteStream, stream)) return;
      session.remoteStream = stream;
      unawaited(_registerRemoteVideo(peerUserId, stream));
      _markPeerState(peerUserId, PeerConnectionState.connected);
      _outgoingTimeoutTimer?.cancel();
      _setState(_state.copyWith(phase: CallPhase.connected, clearError: true));
    };

    pc.onConnectionState = (connectionState) {
      session.connectionState = connectionState;
      switch (connectionState) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _markPeerState(peerUserId, PeerConnectionState.connected);
          _outgoingTimeoutTimer?.cancel();
          _setState(
              _state.copyWith(phase: CallPhase.connected, clearError: true));
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _markPeerState(peerUserId, PeerConnectionState.disconnected);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _markPeerState(peerUserId, PeerConnectionState.failed);
        default:
          break;
      }
    };

    if (isOfferer) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSignal({
        'action': 'offer',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'toUserId': peerUserId,
        'mediaType': _state.mediaKind.wireName,
        'sdpType': offer.type,
        'sdp': offer.sdp,
      });
    }
    return session;
  }

  void _registerSelfParticipant(CallMediaKind mediaKind) {
    final selfUserId = _state.selfUserId ?? _currentUserId();
    if (selfUserId == null) return;
    final existing = _state.self;
    final nextSelf = (existing ??
            CallParticipant(
              userId: selfUserId,
              displayName: _selfDisplayName(),
              state: PeerConnectionState.connected,
            ))
        .copyWith(
      localViewId: existing?.localViewId ?? _localViewId,
      state: PeerConnectionState.connected,
    );
    _setState(_state
        .copyWith(mediaKind: mediaKind, selfUserId: selfUserId)
        .addParticipant(nextSelf));
  }

  Future<void> _registerRemoteVideo(int peerUserId, MediaStream stream) async {
    // 语音通话不需要画面：远端音频由 WebRTC 直接播放。
    if (_state.mediaKind != CallMediaKind.video) return;
    final viewId = _newViewId('remote-$peerUserId');
    await CallMediaRegistry.register(viewId, stream);
    final session = _peers[peerUserId];
    if (session == null) {
      await CallMediaRegistry.release(viewId);
      return;
    }
    await CallMediaRegistry.release(session.remoteViewId);
    session.remoteViewId = viewId;
    _setState(_state.updateParticipant(
      peerUserId,
      (participant) => participant.copyWith(
        remoteViewId: viewId,
        state: PeerConnectionState.connected,
      ),
    ));
  }

  Future<CallIceConfig> _loadIceConfig() async {
    final now = DateTime.now().toUtc();
    final cached = _cachedIceConfig;
    if (cached != null && cached.canReuse(now)) return cached;
    try {
      final config = await _fetchIceConfig(now: now);
      _cacheIceConfig(config);
      return config;
    } catch (_) {
      final fallback = CallIceConfig.fallback(now: now);
      _cacheIceConfig(fallback);
      _setState(_state.copyWith(errorMessage: '通话可能受限'));
      return fallback;
    }
  }

  Future<CallIceConfig> _fetchIceConfig({DateTime? now}) async {
    final response = await _authService.authenticatedRequest(
      'GET',
      ApiConstants.iceServers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('ICE server endpoint failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return CallIceConfig.fromApiResponse(
      decoded,
      now: now ?? DateTime.now().toUtc(),
    );
  }

  void _cacheIceConfig(CallIceConfig config) {
    _cachedIceConfig = config;
    _iceConfigRefreshTimer?.cancel();
    if (_disposed) return;
    var delay = config.expiresAt
        .subtract(const Duration(seconds: 60))
        .difference(DateTime.now().toUtc());
    if (delay.isNegative) delay = const Duration(seconds: 30);
    _iceConfigRefreshTimer = Timer(delay, () {
      unawaited(_refreshIceConfigSilently());
    });
  }

  Future<void> _refreshIceConfigSilently() async {
    if (_disposed) return;
    try {
      _cacheIceConfig(await _fetchIceConfig());
    } catch (_) {
      // 保留现有配置；下一通电话拿不到新凭证时才回退。
    }
  }

  bool _isCurrentCall(Map<String, dynamic> signal) {
    final signalCallId = signal['callId']?.toString();
    return signalCallId != null &&
        signalCallId == _state.callId &&
        _asInt(signal['chatRoomId']) == _state.chatRoomId;
  }

  void _sendJoin() {
    _sendSignal({
      'action': 'join',
      'chatRoomId': _state.chatRoomId,
      'callId': _state.callId,
      'mediaType': _state.mediaKind.wireName,
    });
  }

  void _sendSignal(Map<String, dynamic> signal) {
    if (!_webSocketService.sendCallSignal(signal)) {
      _fail('实时连接未建立，无法发送通话信令');
    }
  }

  void _handleCallRinging(Map<String, dynamic> signal) {
    if (!_isCurrentCall(signal)) return;
    if (_state.phase == CallPhase.outgoing) {
      _setState(_state.copyWith(phase: CallPhase.ringing, clearError: true));
    }
  }

  void _startOutgoingTimeout(String callId) {
    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_state.callId == callId &&
          (_state.phase == CallPhase.outgoing ||
              _state.phase == CallPhase.ringing)) {
        _disposeAllPeers();
        _stopLocalMedia();
        _setState(ChatCallState(
          phase: CallPhase.timeout,
          mediaKind: _state.mediaKind,
          errorMessage: '对方未应答',
          selfUserId: _state.selfUserId,
        ));
      }
    });
  }

  void _markPeerState(int peerUserId, PeerConnectionState state) {
    _setState(_state.updateParticipant(
      peerUserId,
      (participant) => participant.copyWith(state: state),
    ));
  }

  void _endRemote(String message, {CallPhase phase = CallPhase.ended}) {
    _disposeAllPeers();
    _stopLocalMedia();
    _setState(ChatCallState(
      phase: phase,
      mediaKind: _state.mediaKind,
      errorMessage: message,
      selfUserId: _state.selfUserId,
    ));
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (_state.phase == phase) clear();
    });
  }

  void _fail(String message) {
    _disposeAllPeers();
    _stopLocalMedia();
    _setState(ChatCallState(
      phase: CallPhase.failed,
      mediaKind: _state.mediaKind,
      errorMessage: message,
      selfUserId: _state.selfUserId,
    ));
  }

  void _disposeAllPeers() {
    _outgoingTimeoutTimer?.cancel();
    _pendingIce.clear();
    for (final peerUserId in List<int>.from(_peers.keys)) {
      _disposePeerSession(peerUserId);
    }
  }

  void _disposePeerSession(int peerUserId) {
    _pendingIce.remove(peerUserId);
    final session = _peers.remove(peerUserId);
    if (session == null) return;
    unawaited(CallMediaRegistry.release(session.remoteViewId));
    unawaited(session.dispose().catchError((_) {}));
  }

  void _stopLocalMedia() {
    final stream = _localStream;
    _localStream = null;
    unawaited(CallMediaRegistry.release(_localViewId));
    _localViewId = null;
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      unawaited(track.stop().catchError((_) {}));
    }
    unawaited(stream.dispose().catchError((_) {}));
  }

  void _setState(ChatCallState next) {
    if (_disposed) return;
    _state = next;
    ActiveCallTracker.active.value = next.isActive;
    notifyListeners();
  }

  String _knownParticipantName(int userId) {
    for (final participant in _state.participants) {
      if (participant.userId == userId) return participant.displayName;
    }
    return '成员 $userId';
  }

  String _participantName(Map<String, dynamic> signal,
      {required String fallback}) {
    final name = signal['name']?.toString() ?? signal['fromName']?.toString();
    return name == null || name.isEmpty ? fallback : name;
  }

  List<int> _intList(dynamic value) {
    if (value is Iterable) {
      return value.map(_asInt).whereType<int>().toList(growable: false);
    }
    return const [];
  }

  String _selfDisplayName() {
    final user = _authService.currentUser;
    final displayName = user?.displayName;
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final username = user?.username;
    if (username != null && username.isNotEmpty) return username;
    return '我';
  }

  int? _currentUserId() => _asInt(_authService.currentUser?.id);

  String _newCallId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(0x7fffffff).toRadixString(36);
    return 'call-$now-$suffix';
  }

  String _newViewId(String kind) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(0x7fffffff).toRadixString(36);
    return 'pm-chat-$kind-call-$now-$suffix';
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  void dispose() {
    ActiveCallTracker.active.value = false;
    _iceConfigRefreshTimer?.cancel();
    _disposeAllPeers();
    _stopLocalMedia();
    _disposed = true;
    super.dispose();
  }
}

class _PeerSession {
  _PeerSession({required this.peerUserId, required this.pc});

  final int peerUserId;
  final RTCPeerConnection pc;
  MediaStream? remoteStream;
  String? remoteViewId;
  bool remoteDescriptionSet = false;
  RTCPeerConnectionState? connectionState;

  PeerConnectionState get participantState {
    switch (connectionState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return PeerConnectionState.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return PeerConnectionState.disconnected;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return PeerConnectionState.failed;
      default:
        return PeerConnectionState.connecting;
    }
  }

  Future<void> dispose() async {
    pc.onIceCandidate = null;
    pc.onTrack = null;
    pc.onConnectionState = null;
    await pc.close();
  }
}
