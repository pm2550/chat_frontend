part of '../chat_screen.dart';

extension _ChatScreenCallParts on _ChatScreenState {
  Future<void> _handleCallSignal(Map<String, dynamic> signal) async {
    if (signal['chatRoomId']?.toString() != _chat.id || !mounted) {
      return;
    }
    final action = signal['action']?.toString();
    try {
      await _callService.handleSignal(signal);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('通话信令处理失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (_incomingCallDialogVisible &&
        _callService.state.phase != CallPhase.incoming) {
      _dismissIncomingCallDialog();
    }
    if (action == 'invite' && _callService.state.phase == CallPhase.incoming) {
      _showIncomingCallDialog();
    } else if (action == 'reject' || action == 'hangup' || action == 'error') {
      _dismissIncomingCallDialog();
      final label = _callService.state.statusLabel;
      if (label != '未通话') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(label)),
        );
      }
    }
  }

  Future<void> _startCall(CallMediaKind mediaKind) async {
    final label = '${mediaKind.label}通话';
    final roomId = int.tryParse(_chat.id);
    if (roomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label启动失败: 会话编号无效'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      await _webSocketService.connect();
      await _callService.startOutgoingCall(
        chatRoomId: roomId,
        mediaKind: mediaKind,
        peerName: _chat.name,
        peerUserId: _callTargetUserId(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label已发起')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label启动失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showIncomingCallDialog() {
    if (_incomingCallDialogVisible || !mounted) return;
    _incomingCallDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _incomingCallDialogContext = dialogContext;
        return AnimatedBuilder(
          animation: _callService,
          builder: (context, _) {
            final liveState = _callService.state;
            if (liveState.phase != CallPhase.incoming) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                }
              });
              return const SizedBox.shrink();
            }
            return AlertDialog(
              title: Text(
                  '${liveState.primaryPeerName} 的${liveState.mediaKind.label}来电'),
              content: Text(
                _callService.isSupported
                    ? '接听后浏览器会请求麦克风${liveState.isVideo ? '和摄像头' : ''}权限。'
                    : '当前平台暂不支持实时通话。',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _incomingCallDialogVisible = false;
                    _incomingCallDialogContext = null;
                    Navigator.of(dialogContext, rootNavigator: true).pop();
                    _callService.rejectIncoming();
                  },
                  child: const Text('拒绝'),
                ),
                FilledButton.icon(
                  onPressed: _callService.isSupported
                      ? () {
                          _incomingCallDialogVisible = false;
                          _incomingCallDialogContext = null;
                          Navigator.of(dialogContext, rootNavigator: true)
                              .pop();
                          unawaited(_callService.acceptIncoming());
                        }
                      : null,
                  icon: PMSymbolIcon(
                    liveState.isVideo ? PMSymbol.video : PMSymbol.call,
                    size: 18,
                  ),
                  label: const Text('接听'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      _incomingCallDialogVisible = false;
      _incomingCallDialogContext = null;
    });
  }

  void _dismissIncomingCallDialog() {
    final dialogContext = _incomingCallDialogContext;
    if (_incomingCallDialogVisible &&
        dialogContext != null &&
        dialogContext.mounted) {
      Navigator.of(dialogContext, rootNavigator: true).pop();
    }
    _incomingCallDialogVisible = false;
    _incomingCallDialogContext = null;
  }

  int? _callTargetUserId() {
    if (_chat.type != ChatType.private) return null;
    final currentUserId = _authService.currentUser?.id;
    for (final participant in _chat.participants) {
      if (currentUserId == null || participant.id != currentUserId) {
        return int.tryParse(participant.id);
      }
    }
    return null;
  }

  Widget _buildCallPanel() {
    return AnimatedBuilder(
      animation: _callService,
      builder: (context, _) {
        final state = _callService.state;
        if (state.isIdle) {
          return const SizedBox.shrink();
        }
        final isDesktop = PMBreakpoints.isDesktop(context);
        final isTerminal =
            state.phase == CallPhase.ended || state.phase == CallPhase.failed;
        final panel = Container(
          margin: EdgeInsets.fromLTRB(
            isDesktop ? 20 : 12,
            isDesktop ? 14 : 10,
            isDesktop ? 20 : 12,
            0,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [AppColors.appBarShadow],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  PMSymbolIcon(
                    state.isVideo ? PMSymbol.video : PMSymbol.call,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_callPanelTitle(state)} · ${state.mediaKind.label} · ${state.statusLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: isTerminal ? '关闭' : '挂断',
                    onPressed: isTerminal
                        ? _callService.clear
                        : () => unawaited(_callService.hangUp()),
                    icon: PMSymbolIcon(
                      isTerminal ? PMSymbol.close : PMSymbol.callEnd,
                      color: isTerminal ? Colors.white70 : Colors.white,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          isTerminal ? Colors.white12 : AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: _callGridHeight(state, isDesktop),
                child: CallGridView(state: state),
              ),
              if (!state.isVideo)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${state.participants.length}/$kCallMeshParticipantLimit 人 · ${state.statusLabel}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              if (!isTerminal) ...[
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _buildCallControlButton(
                      symbol: (state.self?.micMuted ?? false)
                          ? PMSymbol.micOff
                          : PMSymbol.mic,
                      label: (state.self?.micMuted ?? false) ? '开麦' : '静音',
                      onPressed: _callService.toggleMicrophone,
                    ),
                    if (state.isVideo)
                      _buildCallControlButton(
                        symbol: (state.self?.cameraOff ?? false)
                            ? PMSymbol.videoOff
                            : PMSymbol.video,
                        label:
                            (state.self?.cameraOff ?? false) ? '开摄像头' : '关摄像头',
                        onPressed: _callService.toggleCamera,
                      ),
                    _buildCallControlButton(
                      symbol: PMSymbol.callEnd,
                      label: '挂断',
                      danger: true,
                      onPressed: () => unawaited(_callService.hangUp()),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
        return panel;
      },
    );
  }

  Widget _buildCallControlButton({
    required PMSymbol symbol,
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    return Tooltip(
      message: label,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: danger ? AppColors.error : Colors.white12,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: PMSymbolIcon(symbol, size: 18, color: Colors.white),
        label: Text(label),
      ),
    );
  }

  String _callPanelTitle(ChatCallState state) {
    if (state.others.isEmpty) {
      return _chat.name;
    }
    if (state.others.length == 1) {
      return state.others.first.displayName;
    }
    return '${state.others.length + (state.self == null ? 0 : 1)} 人通话';
  }

  double _callGridHeight(ChatCallState state, bool isDesktop) {
    final count = state.participants.length.clamp(1, kCallMeshParticipantLimit);
    if (state.isVideo) {
      if (count <= 2) return isDesktop ? 280 : 210;
      return isDesktop ? 360 : 280;
    }
    if (count <= 2) return isDesktop ? 170 : 140;
    return isDesktop ? 240 : 210;
  }
}
