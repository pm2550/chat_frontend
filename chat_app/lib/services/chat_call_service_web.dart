import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../constants/api_constants.dart';
import '../models/call_state.dart';
import 'auth_service.dart';
import 'call_ice_config.dart';
import 'call_mesh_policy.dart';
import 'websocket_service.dart';

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
  final Map<int, Future<_PeerSession>> _pendingPeerSessions = {};
  web.MediaStream? _localStream;
  web.HTMLVideoElement? _localVideo;
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
    if (selfUserId != null && fromUserId == selfUserId) {
      return;
    }
    if (toUserId != null && selfUserId != null && toUserId != selfUserId) {
      return;
    }

    switch (action) {
      case 'invite':
        _receiveInvite(signal);
        break;
      case 'call_ringing':
        _handleCallRinging(signal);
        break;
      case 'join_accepted':
        await _handleJoinAccepted(signal);
        break;
      case 'participant_joined':
        await _handleParticipantJoined(signal);
        break;
      case 'participant_left':
        _handleParticipantLeft(signal);
        break;
      case 'error':
        _handleCallError(signal);
        break;
      case 'accept':
        await _handleAccept(signal);
        break;
      case 'reject':
        _endRemote('对方已拒绝通话', phase: CallPhase.declined);
        break;
      case 'offer':
        await _handleOffer(signal);
        break;
      case 'answer':
        await _handleAnswer(signal);
        break;
      case 'ice':
        await _handleIce(signal);
        break;
      case 'hangup':
        _handleParticipantLeft(signal);
        break;
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
      if (_state.phase == CallPhase.ended) {
        clear();
      }
    });
  }

  void toggleMicrophone() {
    final self = _state.self;
    final muted = !(self?.micMuted ?? false);
    for (final track in _localStream?.getAudioTracks().toDart ?? const []) {
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
    final self = _state.self;
    final off = !(self?.cameraOff ?? false);
    for (final track in _localStream?.getVideoTracks().toDart ?? const []) {
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
      final peerName = _knownParticipantName(peerUserId);
      final isOfferer = shouldCreateMeshOffer(
        selfUserId: selfUserId,
        peerUserId: peerUserId,
      );
      await _ensurePeerSession(
        peerUserId,
        peerName: peerName,
        isOfferer: isOfferer,
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

    final peerName = _participantName(signal, fallback: '成员 $peerUserId');
    _outgoingTimeoutTimer?.cancel();
    if (_state.phase != CallPhase.connected) {
      _setState(_state.copyWith(phase: CallPhase.connecting, clearError: true));
    }
    final isOfferer = shouldCreateMeshOffer(
      selfUserId: selfUserId,
      peerUserId: peerUserId,
    );
    await _ensurePeerSession(
      peerUserId,
      peerName: peerName,
      isOfferer: isOfferer,
    );
  }

  void _handleParticipantLeft(Map<String, dynamic> signal) {
    if (!_isCurrentCall(signal)) return;
    final peerUserId = _asInt(signal['userId'] ?? signal['fromUserId']);
    if (peerUserId == null) return;
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
      _fail(
          '通话已满 ${signal['current'] ?? kCallMeshParticipantLimit}/${signal['max'] ?? kCallMeshParticipantLimit}');
      return;
    }
    _fail(error == null || error.isEmpty ? '通话信令失败' : error);
  }

  Future<void> _handleAccept(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    final peerUserId = _asInt(signal['fromUserId']);
    final selfUserId = _state.selfUserId ?? _currentUserId();
    if (peerUserId == null || selfUserId == null) return;

    final isOfferer = shouldCreateMeshOffer(
      selfUserId: selfUserId,
      peerUserId: peerUserId,
    );
    _outgoingTimeoutTimer?.cancel();
    if (_state.phase != CallPhase.connected) {
      _setState(_state.copyWith(phase: CallPhase.connecting, clearError: true));
    }
    await _ensurePeerSession(
      peerUserId,
      peerName: _participantName(signal, fallback: '联系人'),
      isOfferer: isOfferer,
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
    await session.pc
        .setRemoteDescription(web.RTCSessionDescriptionInit(
          type: signal['sdpType']?.toString() ?? 'offer',
          sdp: signal['sdp']?.toString() ?? '',
        ))
        .toDart;
    final answer = await session.pc.createAnswer().toDart;
    if (answer == null) {
      throw StateError('浏览器没有生成 WebRTC answer');
    }
    await session.pc
        .setLocalDescription(web.RTCLocalSessionDescriptionInit(
          type: answer.type,
          sdp: answer.sdp,
        ))
        .toDart;
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
    await session.pc
        .setRemoteDescription(web.RTCSessionDescriptionInit(
          type: signal['sdpType']?.toString() ?? 'answer',
          sdp: signal['sdp']?.toString() ?? '',
        ))
        .toDart;
    _markPeerState(fromUserId, PeerConnectionState.connected);
  }

  Future<void> _handleIce(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    final fromUserId = _asInt(signal['fromUserId']);
    if (fromUserId == null) return;
    final session = _peers[fromUserId];
    if (session == null) return;

    final rawCandidate = signal['candidate'];
    if (rawCandidate is! Map) return;
    final candidate = rawCandidate['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) return;
    await session.pc
        .addIceCandidate(web.RTCIceCandidateInit(
          candidate: candidate,
          sdpMid: rawCandidate['sdpMid']?.toString(),
          sdpMLineIndex: _asInt(rawCandidate['sdpMLineIndex']),
        ))
        .toDart;
  }

  Future<void> _ensureLocalMedia(CallMediaKind mediaKind) async {
    if (_localStream != null) {
      _registerSelfParticipant(mediaKind);
      return;
    }

    final constraints = web.MediaStreamConstraints(
      audio: true.toJS,
      video: (mediaKind == CallMediaKind.video).toJS,
    );
    _localStream = await web.window.navigator.mediaDevices
        .getUserMedia(constraints)
        .toDart;
    _registerLocalVideo(_localStream!, mediaKind);
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
        state: existing.toParticipantState(),
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
        state: session.toParticipantState(),
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
    final pc = web.RTCPeerConnection(web.RTCConfiguration(
      iceServers: _webIceServersFromConfig(iceConfig).toJS,
      iceTransportPolicy: 'all',
      bundlePolicy: 'max-bundle',
      rtcpMuxPolicy: 'require',
    ));
    for (final track in _localStream!.getTracks().toDart) {
      pc.addTrack(track, _localStream!);
    }

    final session = _PeerSession(peerUserId: peerUserId, pc: pc);
    _peers[peerUserId] = session;
    _setState(_state.addParticipant(CallParticipant(
      userId: peerUserId,
      displayName: peerName,
      state: PeerConnectionState.connecting,
    )));

    session.iceSubscription = web.EventStreamProviders.iceCandidateEvent
        .forTarget(pc)
        .listen((event) {
      final candidate = event.candidate;
      if (candidate == null || _state.chatRoomId == null) return;
      final init = candidate.toJSON();
      _sendSignal({
        'action': 'ice',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'toUserId': peerUserId,
        'mediaType': _state.mediaKind.wireName,
        'candidate': {
          'candidate': init.candidate,
          'sdpMid': init.sdpMid,
          'sdpMLineIndex': init.sdpMLineIndex,
        },
      });
    });

    session.trackSubscription =
        web.EventStreamProviders.trackEvent.forTarget(pc).listen((event) {
      final streams = event.streams.toDart;
      session.remoteStream =
          streams.isNotEmpty ? streams.first : web.MediaStream();
      if (streams.isEmpty) {
        session.remoteStream!.addTrack(event.track);
      }
      _registerRemoteVideo(peerUserId, session.remoteStream!);
      _markPeerState(peerUserId, PeerConnectionState.connected);
      _outgoingTimeoutTimer?.cancel();
      _setState(_state.copyWith(phase: CallPhase.connected, clearError: true));
    });

    session.connectionSubscription = web
        .EventStreamProviders.connectionStateChangeEvent
        .forTarget(pc)
        .listen((_) {
      final connectionState = pc.connectionState;
      if (connectionState == 'connected') {
        _markPeerState(peerUserId, PeerConnectionState.connected);
        _outgoingTimeoutTimer?.cancel();
        _setState(
            _state.copyWith(phase: CallPhase.connected, clearError: true));
      } else if (connectionState == 'disconnected') {
        _markPeerState(peerUserId, PeerConnectionState.disconnected);
      } else if (connectionState == 'failed' || connectionState == 'closed') {
        _markPeerState(peerUserId, PeerConnectionState.failed);
      }
    });

    if (isOfferer) {
      final offer = await pc.createOffer().toDart;
      if (offer == null) {
        throw StateError('浏览器没有生成 WebRTC offer');
      }
      await pc
          .setLocalDescription(web.RTCLocalSessionDescriptionInit(
            type: offer.type,
            sdp: offer.sdp,
          ))
          .toDart;
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
      localViewId: existing?.localViewId ?? _currentLocalViewId(),
      state: PeerConnectionState.connected,
    );
    _setState(_state
        .copyWith(mediaKind: mediaKind, selfUserId: selfUserId)
        .addParticipant(nextSelf));
  }

  void _registerLocalVideo(web.MediaStream stream, CallMediaKind mediaKind) {
    if (_localVideo != null) return;
    final viewId = _newViewId('local');
    _localVideo = _buildVideoElement(stream, muted: true);
    ui_web.platformViewRegistry
        .registerViewFactory(viewId, (int _) => _localVideo!);
    final selfUserId = _state.selfUserId ?? _currentUserId();
    if (selfUserId != null) {
      _setState(_state
          .copyWith(mediaKind: mediaKind, selfUserId: selfUserId)
          .addParticipant(CallParticipant(
            userId: selfUserId,
            displayName: _selfDisplayName(),
            localViewId: viewId,
            state: PeerConnectionState.connected,
          )));
    }
  }

  void _registerRemoteVideo(int peerUserId, web.MediaStream stream) {
    final viewId = _newViewId('remote-$peerUserId');
    final video = _buildVideoElement(stream, muted: false);
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) => video);
    final session = _peers[peerUserId];
    if (session != null) {
      session.remoteViewId = viewId;
    }
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
    if (cached != null && cached.canReuse(now)) {
      return cached;
    }

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

    final refreshAt = config.expiresAt.subtract(const Duration(seconds: 60));
    var delay = refreshAt.difference(DateTime.now().toUtc());
    if (delay.isNegative) {
      delay = const Duration(seconds: 30);
    }

    _iceConfigRefreshTimer = Timer(delay, () {
      unawaited(_refreshIceConfigSilently());
    });
  }

  Future<void> _refreshIceConfigSilently() async {
    if (_disposed) return;
    try {
      _cacheIceConfig(await _fetchIceConfig());
    } catch (_) {
      // Keep the existing config. The next call falls back only if fresh TURN
      // credentials cannot be fetched again.
    }
  }

  List<web.RTCIceServer> _webIceServersFromConfig(CallIceConfig config) {
    return config.iceServers
        .map(_webIceServerFromModel)
        .toList(growable: false);
  }

  web.RTCIceServer _webIceServerFromModel(CallIceServer server) {
    JSAny urls;
    if (server.urls.length == 1) {
      urls = server.urls.first.toJS;
    } else {
      urls = server.urls.map((url) => url.toJS).toList(growable: false).toJS;
    }

    if (server.username != null && server.credential != null) {
      return web.RTCIceServer(
        urls: urls,
        username: server.username!,
        credential: server.credential!,
      );
    }
    return web.RTCIceServer(urls: urls);
  }

  web.HTMLVideoElement _buildVideoElement(
    web.MediaStream stream, {
    required bool muted,
  }) {
    final element = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = muted
      ..playsInline = true
      ..srcObject = stream;
    element.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..backgroundColor = '#0f172a'
      ..borderRadius = '12px';
    unawaited(element.play().toDart.catchError((_) => null));
    return element;
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
    final ok = _webSocketService.sendCallSignal(signal);
    if (!ok) {
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
        _timeoutOutgoingCall();
      }
    });
  }

  void _timeoutOutgoingCall() {
    _disposeAllPeers();
    _stopLocalMedia();
    _setState(ChatCallState(
      phase: CallPhase.timeout,
      mediaKind: _state.mediaKind,
      errorMessage: '对方未应答',
      selfUserId: _state.selfUserId,
    ));
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
      if (_state.phase == phase) {
        clear();
      }
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
    for (final peerUserId in List<int>.from(_peers.keys)) {
      _disposePeerSession(peerUserId);
    }
  }

  void _disposePeerSession(int peerUserId) {
    final session = _peers.remove(peerUserId);
    try {
      session?.dispose();
    } catch (_) {
      // Peer cleanup should never surface as a call signaling failure.
    }
  }

  void _stopLocalMedia() {
    for (final track in _localStream?.getTracks().toDart ?? const []) {
      track.stop();
    }
    _localStream = null;
    _localVideo = null;
  }

  void _setState(ChatCallState next) {
    _state = next;
    notifyListeners();
  }

  String? _currentLocalViewId() {
    final self = _state.self;
    return self?.localViewId;
  }

  String _knownParticipantName(int userId) {
    for (final participant in _state.participants) {
      if (participant.userId == userId) {
        return participant.displayName;
      }
    }
    return '成员 $userId';
  }

  String _participantName(
    Map<String, dynamic> signal, {
    required String fallback,
  }) {
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
    _disposed = true;
    _iceConfigRefreshTimer?.cancel();
    _disposeAllPeers();
    _stopLocalMedia();
    super.dispose();
  }
}

class _PeerSession {
  _PeerSession({
    required this.peerUserId,
    required this.pc,
  }) : createdAt = DateTime.now().toUtc();

  final int peerUserId;
  final web.RTCPeerConnection pc;
  final DateTime createdAt;
  web.MediaStream? remoteStream;
  String? remoteViewId;
  StreamSubscription<web.RTCPeerConnectionIceEvent>? iceSubscription;
  StreamSubscription<web.RTCTrackEvent>? trackSubscription;
  StreamSubscription<web.Event>? connectionSubscription;

  PeerConnectionState toParticipantState() {
    final state = pc.connectionState;
    if (state == 'connected') return PeerConnectionState.connected;
    if (state == 'disconnected') return PeerConnectionState.disconnected;
    if (state == 'failed' || state == 'closed') {
      return PeerConnectionState.failed;
    }
    return PeerConnectionState.connecting;
  }

  void dispose() {
    iceSubscription?.cancel();
    trackSubscription?.cancel();
    connectionSubscription?.cancel();
    try {
      for (final track in remoteStream?.getTracks().toDart ?? const []) {
        track.stop();
      }
    } catch (_) {
      // Some browsers expose remote stream tracks as native JS arrays that can
      // outlive Dart's typed wrapper during teardown. Closing the peer
      // connection below is the authoritative cleanup.
    }
    pc.close();
  }
}
