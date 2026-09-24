import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/message.dart';
import '../../services/chat_data_service.dart';

/// 一个聊天室的置顶消息状态，按后端 `GET /rooms/{id}/pins` 的顺序保存
/// （最新置顶在前）。
///
/// 权限与后端 RoomPinController 一致：私聊双方都能置顶/取消置顶；群聊只有
/// 群主和管理员可以。所有成员都能看到置顶列表。
///
/// 实时同步：收到 `pin_added` / `pin_removed` 推送时，事件里带着完整的
/// `pins` 列表，调用 [applyServerPins] 即可；不带列表时调用 [load] 重新拉取。
class PinnedMessagesController extends ChangeNotifier {
  PinnedMessagesController({
    required ChatDataService chatService,
    required String Function() roomId,
  })  : _chatService = chatService,
        _roomId = roomId;

  final ChatDataService _chatService;
  final String Function() _roomId;

  List<Message> _pins = const [];
  bool _isGroup = false;
  bool _viewerIsAdmin = false;
  int _loadGeneration = 0;
  bool _disposed = false;

  List<Message> get pins => _pins;
  Message? get latest => _pins.isEmpty ? null : _pins.first;
  bool isPinned(String messageId) => _pins.any((m) => m.id == messageId);

  /// 当前用户能否置顶/取消置顶。
  bool get canManage => !_isGroup || _viewerIsAdmin;

  void updatePermissions({required bool isGroup, required bool viewerIsAdmin}) {
    if (_isGroup == isGroup && _viewerIsAdmin == viewerIsAdmin) return;
    _isGroup = isGroup;
    _viewerIsAdmin = viewerIsAdmin;
    _notify();
  }

  /// 从服务器拉取置顶列表。失败时保留现有列表（置顶条是辅助信息，不能让
  /// 聊天页因此报错）。
  Future<void> load() async {
    final roomId = _roomId();
    if (roomId.trim().isEmpty) return;
    final generation = ++_loadGeneration;
    try {
      final pins = await _chatService.getPinnedMessages(roomId);
      if (_disposed || generation != _loadGeneration) return;
      _pins = List<Message>.unmodifiable(pins);
      _notify();
    } catch (_) {
      // Keep whatever we had; the next pin action or realtime event refreshes.
    }
  }

  /// 用服务器返回的完整置顶列表替换本地状态（REST 响应或实时推送）。
  void applyServerPins(List<Message> pins) {
    _loadGeneration++;
    _pins = List<Message>.unmodifiable(pins);
    _notify();
  }

  Future<void> pin(String messageId) async {
    final pins = await _chatService.pinMessage(_roomId(), messageId);
    applyServerPins(pins);
  }

  Future<void> unpin(String messageId) async {
    final pins = await _chatService.unpinMessage(_roomId(), messageId);
    applyServerPins(pins);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String pinnedMessagePreview(Message message) {
  if (message.isRemoved) return '该消息已删除';
  final text = message.resolvedFileLabel.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.isEmpty ? '[消息]' : text;
}

/// 聊天顶部的置顶条：显示最新一条置顶，点击打开完整列表。
class PinnedMessagesBar extends StatelessWidget {
  const PinnedMessagesBar({
    super.key,
    required this.controller,
    required this.onOpenList,
  });

  final PinnedMessagesController controller;
  final VoidCallback onOpenList;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final latest = controller.latest;
        if (latest == null) return const SizedBox.shrink();
        final count = controller.pins.length;
        return Material(
          key: const ValueKey('pinned-messages-bar'),
          color: AppColors.primary.withValues(alpha: 0.06),
          child: InkWell(
            onTap: onOpenList,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PMSpacing.l,
                vertical: PMSpacing.s,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.borderLight),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.push_pin_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: PMSpacing.s),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: count > 1 ? '置顶 · $count 条  ' : '置顶  ',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text:
                                '${latest.senderName}：${pinnedMessagePreview(latest)}',
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 置顶消息列表面板。点某一条跳到消息位置；有权限时每条带“取消置顶”。
Future<void> showPinnedMessagesSheet(
  BuildContext context, {
  required PinnedMessagesController controller,
  required ValueChanged<Message> onJumpTo,
  required Future<void> Function(Message message) onUnpin,
  required String Function(DateTime timestamp) formatTime,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final pins = controller.pins;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: PMDialogHeader(
                      title: '置顶消息',
                      subtitle: controller.canManage
                          ? '点击跳到消息位置'
                          : '点击跳到消息位置 · 仅群主和管理员可以取消置顶',
                    ),
                  ),
                  if (pins.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '没有置顶消息',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: pins.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final message = pins[index];
                          return PMListRow(
                            key: ValueKey('pinned-message-${message.id}'),
                            dense: true,
                            leading: const Icon(
                              Icons.push_pin_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            title: Text(
                              pinnedMessagePreview(message),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${message.senderName} · ${formatTime(message.timestamp)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: controller.canManage
                                ? IconButton(
                                    tooltip: '取消置顶',
                                    icon: const Icon(
                                      Icons.push_pin_rounded,
                                      color: AppColors.textSecondary,
                                    ),
                                    onPressed: () => onUnpin(message),
                                  )
                                : null,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              onJumpTo(message);
                            },
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
