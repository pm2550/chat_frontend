import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/os_dropped_files.dart';

/// 接收从操作系统（文件管理器、浏览器下载栏……）拖进来的文件。
///
/// 桌面端（Windows/macOS/Linux）用 desktop_drop 的原生实现，Web 端用它的
/// DOM 实现。只在自己可见时接收：被别的页面盖住、或者在没选中的 Tab 里时，
/// 不能把别人那边的拖放吃掉。
class OsFileDropTarget extends StatefulWidget {
  const OsFileDropTarget({
    super.key,
    required this.child,
    required this.onFilesDropped,
    this.onDragActiveChanged,
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<DroppedFileBatch> onFilesDropped;
  final ValueChanged<bool>? onDragActiveChanged;
  final bool enabled;

  static bool supportedOn({required bool web, required TargetPlatform platform}) {
    if (web) return true;
    return platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
  }

  static bool get supported =>
      supportedOn(web: kIsWeb, platform: defaultTargetPlatform);

  @override
  State<OsFileDropTarget> createState() => _OsFileDropTargetState();
}

class _OsFileDropTargetState extends State<OsFileDropTarget> {
  bool _active = false;

  void _setActive(bool active) {
    if (_active == active) return;
    _active = active;
    widget.onDragActiveChanged?.call(active);
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    final enabled = widget.enabled && visible && OsFileDropTarget.supported;
    if (!enabled && _active) {
      // 拖到一半页面被盖住了：把高亮收起来。
      scheduleMicrotask(() => _setActive(false));
    }
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => _setActive(true),
      onDragExited: (_) => _setActive(false),
      onDragDone: (details) {
        _setActive(false);
        unawaited(readDroppedItems(details.files).then((batch) {
          if (mounted) widget.onFilesDropped(batch);
        }));
      },
      child: widget.child,
    );
  }
}
