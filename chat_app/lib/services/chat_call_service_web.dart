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

  web.RTCPeerConnection? _peerConnection;
  web.MediaStream? _localStream;
  web.MediaStream? _remoteStream;
  web.HTMLVideoElement? _localVideo;
  web.HTMLVideoElement? _remoteVideo;
  StreamSubscription<web.RTCPeerConnectionIceEvent>? _iceSubscription;
  StreamSubscription<web.RTCTrackEvent>? _trackSubscription;
  StreamSubscription<web.Event>? _connectionSubscription;

  Future<void> startOutgoingCall({
    required int chatRoomId,
    required CallMediaKind mediaKind,
    required String peerName,
  }) async {
    if (_state.isActive) {
      await hangUp(sendSignal: true);
    }

    final callId = _newCallId();
    _setState(ChatCallState(
      phase: CallPhase.outgoing,
      callId: callId,
      chatRoomId: chatRoomId,
      peerName: peerName,
      mediaKind: mediaKind,
    ));

    try {
      await _preparePeer(mediaKind);
      _sendSignal({
        'action': 'invite',
        'chatRoomId': chatRoomId,
        'callId': callId,
        'mediaType': mediaKind.wireName,
      });
    } catch (error) {
      _fail('无法启动${mediaKind.label}通话: $error');
    }
  }

  Future<void> handleSignal(Map<String, dynamic> signal) async {
    final action = signal['action']?.toString();
    final fromUserId = _asInt(signal['fromUserId']);
    final toUserId = _asInt(signal['toUserId']);
    final selfUserId = _asInt(_authService.currentUser?.id);
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
      case 'accept':
        await _handleAccept(signal);
        break;
      case 'reject':
        _endRemote('对方已拒绝通话');
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
        _endRemote('通话已结束');
        break;
    }
  }

  Future<void> acceptIncoming() async {
    if (_state.phase != CallPhase.incoming ||
        _state.chatRoomId == null ||
        _state.callId == null ||
        _state.peerUserId == null) {
      return;
    }
    try {
      await _preparePeer(_state.mediaKind);
      _setState(_state.copyWith(phase: CallPhase.connecting, clearError: true));
      _sendSignal({
        'action': 'accept',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'toUserId': _state.peerUserId,
        'mediaType': _state.mediaKind.wireName,
      });
    } catch (error) {
      _sendSignal({
        'action': 'reject',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'toUserId': _state.peerUserId,
        'mediaType': _state.mediaKind.wireName,
      });
      _fail('无法接听${_state.mediaKind.label}通话: $error');
    }
  }

  void rejectIncoming() {
    if (_state.phase == CallPhase.incoming) {
      _sendSignal({
        'action': 'reject',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'toUserId': _state.peerUserId,
        'mediaType': _state.mediaKind.wireName,
      });
    }
    clear();
  }

  Future<void> hangUp({bool sendSignal = true}) async {
    if (sendSignal && _state.isActive) {
      _sendSignal({
        'action': 'hangup',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        if (_state.peerUserId != null) 'toUserId': _state.peerUserId,
        'mediaType': _state.mediaKind.wireName,
      });
    }
    _disposePeer();
    _setState(const ChatCallState(phase: CallPhase.ended));
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (_state.phase == CallPhase.ended) {
        clear();
      }
    });
  }

  void toggleMicrophone() {
    final muted = !_state.microphoneMuted;
    for (final track in _localStream?.getAudioTracks().toDart ?? const []) {
      track.enabled = !muted;
    }
    _setState(_state.copyWith(microphoneMuted: muted));
  }

  void toggleCamera() {
    final off = !_state.cameraOff;
    for (final track in _localStream?.getVideoTracks().toDart ?? const []) {
      track.enabled = !off;
    }
    _setState(_state.copyWith(cameraOff: off));
  }

  void clear() {
    _disposePeer();
    _setState(const ChatCallState());
  }

  void _receiveInvite(Map<String, dynamic> signal) {
    if (_state.isActive) {
      _sendSignal({
        'action': 'reject',
        'chatRoomId': _asInt(signal['chatRoomId']),
        'callId': signal['callId']?.toString(),
        'toUserId': _asInt(signal['fromUserId']),
        'mediaType': CallMediaKind.fromWire(signal['mediaType']).wireName,
      });
      return;
    }
    _setState(ChatCallState(
      phase: CallPhase.incoming,
      callId: signal['callId']?.toString(),
      chatRoomId: _asInt(signal['chatRoomId']),
      peerUserId: _asInt(signal['fromUserId']),
      peerName: signal['fromName']?.toString(),
      mediaKind: CallMediaKind.fromWire(signal['mediaType']),
    ));
  }

  Future<void> _handleAccept(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal) || _state.phase != CallPhase.outgoing) {
      return;
    }
    final peerUserId = _asInt(signal['fromUserId']);
    if (peerUserId == null) return;
    _setState(_state.copyWith(
      phase: CallPhase.connecting,
      peerUserId: peerUserId,
      peerName: signal['fromName']?.toString(),
      clearError: true,
    ));
    await _ensurePeer();
    final offer = await _peerConnection!.createOffer().toDart;
    if (offer == null) {
      throw StateError('浏览器没有生成 WebRTC offer');
    }
    await _peerConnection!
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

  Future<void> _handleOffer(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal)) return;
    await _ensurePeer();
    final fromUserId = _asInt(signal['fromUserId']);
    _setState(_state.copyWith(
      phase: CallPhase.connecting,
      peerUserId: fromUserId,
      peerName: signal['fromName']?.toString(),
      clearError: true,
    ));
    await _peerConnection!
        .setRemoteDescription(web.RTCSessionDescriptionInit(
          type: signal['sdpType']?.toString() ?? 'offer',
          sdp: signal['sdp']?.toString() ?? '',
        ))
        .toDart;
    final answer = await _peerConnection!.createAnswer().toDart;
    if (answer == null) {
      throw StateError('浏览器没有生成 WebRTC answer');
    }
    await _peerConnection!
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
    if (!_isCurrentCall(signal) || _peerConnection == null) return;
    await _peerConnection!
        .setRemoteDescription(web.RTCSessionDescriptionInit(
          type: signal['sdpType']?.toString() ?? 'answer',
          sdp: signal['sdp']?.toString() ?? '',
        ))
        .toDart;
    _setState(_state.copyWith(phase: CallPhase.connected, clearError: true));
  }

  Future<void> _handleIce(Map<String, dynamic> signal) async {
    if (!_isCurrentCall(signal) || _peerConnection == null) return;
    final rawCandidate = signal['candidate'];
    if (rawCandidate is! Map) return;
    final candidate = rawCandidate['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) return;
    await _peerConnection!
        .addIceCandidate(web.RTCIceCandidateInit(
          candidate: candidate,
          sdpMid: rawCandidate['sdpMid']?.toString(),
          sdpMLineIndex: _asInt(rawCandidate['sdpMLineIndex']),
        ))
        .toDart;
  }

  Future<void> _preparePeer(CallMediaKind mediaKind) async {
    _disposePeer();
    final constraints = web.MediaStreamConstraints(
      audio: true.toJS,
      video: (mediaKind == CallMediaKind.video).toJS,
    );
    _localStream = await web.window.navigator.mediaDevices
        .getUserMedia(constraints)
        .toDart;
    final iceServers = await _loadIceServers();
    _peerConnection = web.RTCPeerConnection(web.RTCConfiguration(
      iceServers: iceServers.toJS,
    ));

    _registerLocalVideo(_localStream!, mediaKind);
    for (final track in _localStream!.getTracks().toDart) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    _iceSubscription = web.EventStreamProviders.iceCandidateEvent
        .forTarget(_peerConnection)
        .listen((event) {
      final candidate = event.candidate;
      if (candidate == null ||
          _state.chatRoomId == null ||
          _state.callId == null ||
          _state.peerUserId == null) {
        return;
      }
      final init = candidate.toJSON();
      _sendSignal({
        'action': 'ice',
        'chatRoomId': _state.chatRoomId,
        'callId': _state.callId,
        'toUserId': _state.peerUserId,
        'mediaType': _state.mediaKind.wireName,
        'candidate': {
          'candidate': init.candidate,
          'sdpMid': init.sdpMid,
          'sdpMLineIndex': init.sdpMLineIndex,
        },
      });
    });

    _trackSubscription = web.EventStreamProviders.trackEvent
        .forTarget(_peerConnection)
        .listen((event) {
      final streams = event.streams.toDart;
      _remoteStream = streams.isNotEmpty ? streams.first : web.MediaStream();
      if (streams.isEmpty) {
        _remoteStream!.addTrack(event.track);
      }
      _registerRemoteVideo(_remoteStream!, _state.mediaKind);
      _setState(_state.copyWith(
        phase: CallPhase.connected,
        remoteViewId: _state.remoteViewId,
        clearError: true,
      ));
    });

    _connectionSubscription = web
        .EventStreamProviders.connectionStateChangeEvent
        .forTarget(_peerConnection)
        .listen((_) {
      final state = _peerConnection?.connectionState;
      if (state == 'connected') {
        _setState(
            _state.copyWith(phase: CallPhase.connected, clearError: true));
      } else if (state == 'failed' ||
          state == 'disconnected' ||
          state == 'closed') {
        _fail('媒体连接已断开');
      }
    });
  }

  Future<void> _ensurePeer() async {
    if (_peerConnection == null || _localStream == null) {
      await _preparePeer(_state.mediaKind);
    }
  }

  void _registerLocalVideo(web.MediaStream stream, CallMediaKind mediaKind) {
    final viewId = _newViewId('local');
    _localVideo = _buildVideoElement(stream, muted: true);
    ui_web.platformViewRegistry
        .registerViewFactory(viewId, (int _) => _localVideo!);
    _setState(_state.copyWith(localViewId: viewId, mediaKind: mediaKind));
  }

  web.RTCIceServer _buildIceServer(String url) {
    final lowerUrl = url.toLowerCase();
    final requiresCredentials =
        lowerUrl.startsWith('turn:') || lowerUrl.startsWith('turns:');
    if (requiresCredentials && ApiConstants.hasWebrtcTurnCredentials) {
      return web.RTCIceServer(
        urls: url.toJS,
        username: ApiConstants.webrtcTurnUsername,
        credential: ApiConstants.webrtcTurnCredential,
      );
    }
    return web.RTCIceServer(urls: url.toJS);
  }

  Future<List<web.RTCIceServer>> _loadIceServers() async {
    try {
      final response = await _authService.authenticatedRequest(
        'GET',
        ApiConstants.callIceServers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final payload = decoded is Map<String, dynamic>
            ? decoded['data'] ?? decoded
            : decoded;
        if (payload is Map<String, dynamic>) {
          final rawServers = payload['iceServers'];
          if (rawServers is List) {
            final servers = rawServers
                .whereType<Map>()
                .map(_iceServerFromJson)
                .whereType<web.RTCIceServer>()
                .toList(growable: false);
            if (servers.isNotEmpty) {
              return servers;
            }
          }
        }
      }
    } catch (_) {
      // Fall back to build-time STUN config below.
    }
    return ApiConstants.webrtcIceServers
        .map(_buildIceServer)
        .toList(growable: false);
  }

  web.RTCIceServer? _iceServerFromJson(Map<dynamic, dynamic> json) {
    final rawUrls = json['urls'];
    JSAny urls;
    if (rawUrls is List) {
      final parsed = rawUrls
          .map((url) => url.toString().trim())
          .where((url) => url.isNotEmpty)
          .map((url) => url.toJS)
          .toList(growable: false);
      if (parsed.isEmpty) return null;
      urls = parsed.toJS;
    } else {
      final url = rawUrls?.toString().trim() ?? '';
      if (url.isEmpty) return null;
      urls = url.toJS;
    }

    final username = json['username']?.toString();
    final credential = json['credential']?.toString();
    if (username != null &&
        username.isNotEmpty &&
        credential != null &&
        credential.isNotEmpty) {
      return web.RTCIceServer(
        urls: urls,
        username: username,
        credential: credential,
      );
    }
    return web.RTCIceServer(urls: urls);
  }

  void _registerRemoteVideo(web.MediaStream stream, CallMediaKind mediaKind) {
    final viewId = _newViewId('remote');
    _remoteVideo = _buildVideoElement(stream, muted: false);
    ui_web.platformViewRegistry
        .registerViewFactory(viewId, (int _) => _remoteVideo!);
    _setState(_state.copyWith(remoteViewId: viewId, mediaKind: mediaKind));
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

  void _sendSignal(Map<String, dynamic> signal) {
    final ok = _webSocketService.sendCallSignal(signal);
    if (!ok) {
      _fail('实时连接未建立，无法发送通话信令');
    }
  }

  void _endRemote(String message) {
    _disposePeer();
    _setState(ChatCallState(
      phase: CallPhase.ended,
      mediaKind: _state.mediaKind,
      errorMessage: message,
    ));
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (_state.phase == CallPhase.ended) {
        clear();
      }
    });
  }

  void _fail(String message) {
    _disposePeer();
    _setState(ChatCallState(
      phase: CallPhase.failed,
      mediaKind: _state.mediaKind,
      errorMessage: message,
    ));
  }

  void _disposePeer() {
    _iceSubscription?.cancel();
    _trackSubscription?.cancel();
    _connectionSubscription?.cancel();
    _iceSubscription = null;
    _trackSubscription = null;
    _connectionSubscription = null;
    for (final track in _localStream?.getTracks().toDart ?? const []) {
      track.stop();
    }
    for (final track in _remoteStream?.getTracks().toDart ?? const []) {
      track.stop();
    }
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _localVideo = null;
    _remoteVideo = null;
  }

  void _setState(ChatCallState next) {
    _state = next;
    notifyListeners();
  }

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
    _disposePeer();
    super.dispose();
  }
}
