import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_version.dart';
import '../services/device_abi.dart';
import '../services/update_service.dart';
import '../services/websocket_service.dart';
import 'update_dialog.dart';

class AppUpdateListener extends StatefulWidget {
  final Widget child;
  final Stream<Map<String, dynamic>>? updateEvents;
  final String? currentPlatform;

  /// 本机 Android ABI；测试里替换，默认 [DeviceAbi.current]。
  final Future<String?> Function()? deviceAbi;
  final Future<void> Function(BuildContext context, AppVersionCheck check)?
      showUpdate;

  const AppUpdateListener({
    super.key,
    required this.child,
    this.updateEvents,
    this.currentPlatform,
    this.deviceAbi,
    this.showUpdate,
  });

  @override
  State<AppUpdateListener> createState() => _AppUpdateListenerState();
}

class _AppUpdateListenerState extends State<AppUpdateListener> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant AppUpdateListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updateEvents != widget.updateEvents) {
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription?.cancel();
    final stream =
        widget.updateEvents ?? WebSocketService().onAppUpdateAvailable;
    _subscription = stream.listen(_handleUpdateEvent);
  }

  Future<void> _handleUpdateEvent(Map<String, dynamic> event) async {
    if (_showing || !mounted) return;
    if (!UpdateService.shouldHandleUpdateForPlatform(
      event['platform']?.toString(),
      currentPlatform: widget.currentPlatform,
    )) {
      return;
    }

    final check = UpdateService.checkFromWebSocketPayload(event);
    if (!check.updateAvailable) return;

    _showing = true;
    try {
      final deviceAbi = await (widget.deviceAbi ?? DeviceAbi.current)();
      if (!mounted ||
          !UpdateService.shouldHandleUpdateForAbi(check.abi, deviceAbi)) {
        return;
      }
      final showUpdate = widget.showUpdate;
      if (showUpdate != null) {
        await showUpdate(context, check);
      } else {
        await UpdateDialog.show(context, check, reloadWeb: false);
      }
    } finally {
      _showing = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
