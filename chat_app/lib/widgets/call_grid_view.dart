import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../design/design.dart';
import '../models/call_state.dart';
import 'call_media_view.dart';

class CallGridView extends StatelessWidget {
  const CallGridView({
    super.key,
    required this.state,
  });

  final ChatCallState state;

  @override
  Widget build(BuildContext context) {
    final participants = state.participants.isEmpty
        ? [
            CallParticipant(
              userId: state.selfUserId ?? -1,
              displayName: state.statusLabel,
            ),
          ]
        : state.participants;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(
          participants.length,
          constraints.maxWidth,
        );
        final spacing = participants.length == 1 ? 0.0 : PMSpacing.s;
        final tileHeight = _tileHeight(
          constraints.maxHeight,
          participants.length,
          columns,
          spacing,
        );

        if (participants.length == 1) {
          return _CallTile(
            participant: participants.first,
            isSelf: participants.first.userId == state.selfUserId,
            mediaKind: state.mediaKind,
            height: constraints.maxHeight,
          );
        }

        return AnimatedSwitcher(
          duration: PMMotion.medium,
          switchInCurve: PMMotion.curveStandard,
          switchOutCurve: PMMotion.curveStandard,
          child: GridView.builder(
            key: ValueKey('${participants.length}-$columns'),
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: tileHeight,
            ),
            itemCount: participants.length,
            itemBuilder: (context, index) {
              final participant = participants[index];
              return _CallTile(
                participant: participant,
                isSelf: participant.userId == state.selfUserId,
                mediaKind: state.mediaKind,
                height: tileHeight,
              );
            },
          ),
        );
      },
    );
  }

  int _columnsFor(int count, double width) {
    if (count <= 1) return 1;
    if (width < 520) return count <= 2 ? 1 : 2;
    if (count <= 4) return 2;
    return 3;
  }

  double _tileHeight(
    double maxHeight,
    int count,
    int columns,
    double spacing,
  ) {
    if (!maxHeight.isFinite || maxHeight <= 0) {
      return 180;
    }
    final rows = (count / columns).ceil().clamp(1, 3).toInt();
    return ((maxHeight - spacing * (rows - 1)) / rows).clamp(112, 360);
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.participant,
    required this.isSelf,
    required this.mediaKind,
    required this.height,
  });

  final CallParticipant participant;
  final bool isSelf;
  final CallMediaKind mediaKind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final status = _statusStyle(participant.state);
    final viewId = isSelf ? participant.localViewId : participant.remoteViewId;
    final cameraOff = mediaKind == CallMediaKind.video && participant.cameraOff;
    final label = cameraOff
        ? '摄像头已关'
        : isSelf
            ? '本机'
            : participant.displayName;

    return AnimatedContainer(
      duration: PMMotion.medium,
      curve: PMMotion.curveStandard,
      height: height,
      padding: EdgeInsets.all(participant.anonymous ? 2 : 0),
      decoration: BoxDecoration(
        gradient: participant.anonymous
            ? const LinearGradient(
                colors: [Color(0xFF7C3AED), AppColors.secondary],
              )
            : null,
        borderRadius: BorderRadius.circular(PMRadius.l),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PMRadius.l),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CallMediaView(
              viewId: cameraOff ? null : viewId,
              label: label,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.20),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.56),
                  ],
                ),
              ),
            ),
            Positioned(
              left: PMSpacing.m,
              right: PMSpacing.m,
              bottom: PMSpacing.m,
              child: Row(
                children: [
                  _StatusDot(color: status.$1),
                  const SizedBox(width: PMSpacing.s),
                  Expanded(
                    child: Text(
                      isSelf
                          ? '${participant.displayName}（我）'
                          : participant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (participant.micMuted)
                    const PMSymbolIcon(
                      PMSymbol.micOff,
                      size: 18,
                      color: Colors.white,
                    ),
                  if (mediaKind == CallMediaKind.video && participant.cameraOff)
                    const Padding(
                      padding: EdgeInsets.only(left: PMSpacing.xs),
                      child: PMSymbolIcon(
                        PMSymbol.videoOff,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: PMSpacing.m,
              left: PMSpacing.m,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  borderRadius: BorderRadius.circular(PMRadius.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PMSpacing.s,
                    vertical: PMSpacing.xs,
                  ),
                  child: Text(
                    status.$2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, String) _statusStyle(PeerConnectionState state) {
    return switch (state) {
      PeerConnectionState.connected => (AppColors.success, '已连接'),
      PeerConnectionState.connecting => (AppColors.warning, '连接中'),
      PeerConnectionState.disconnected => (AppColors.warning, '重连中'),
      PeerConnectionState.failed => (AppColors.error, '失败'),
    };
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.40),
            blurRadius: 8,
          ),
        ],
      ),
      child: const SizedBox.square(dimension: 9),
    );
  }
}
