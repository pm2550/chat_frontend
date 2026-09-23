import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_media_registry_native.dart';

class CallMediaView extends StatelessWidget {
  const CallMediaView({
    super.key,
    required this.viewId,
    required this.label,
  });

  final String? viewId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final id = viewId;
    final renderer = id == null ? null : CallMediaRegistry.renderer(id);
    if (renderer == null) {
      return _CallMediaPlaceholder(label: label);
    }
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: RTCVideoView(
        renderer,
        mirror: CallMediaRegistry.isMirrored(id!),
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}

class _CallMediaPlaceholder extends StatelessWidget {
  const _CallMediaPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFF0F172A),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
