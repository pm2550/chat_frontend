import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/encryption_service.dart';

/// 聊天头部的锁：只在这个私聊真的在加密时显示。
class E2eeHeaderBadge extends StatelessWidget {
  const E2eeHeaderBadge({super.key, required this.state, this.fontSize = 12});

  final E2eeRoomState state;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (!state.encrypts) return const SizedBox.shrink();
    return Tooltip(
      message: '消息只有你和对方的设备能解密，服务器也看不到内容',
      child: Row(
        key: const ValueKey('e2ee-header-badge'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: fontSize + 1, color: AppColors.success),
          const SizedBox(width: 3),
          Text(
            '端到端加密',
            style: TextStyle(
              fontSize: fontSize,
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 聊天顶部的提示条：对方没开、有机器人、本机未解锁、对方密钥变了。
class E2eeRoomNoticeBar extends StatelessWidget {
  const E2eeRoomNoticeBar({super.key, required this.state, this.onUnlock});

  final E2eeRoomState state;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final notice = state.notice;
    if (notice == null) return const SizedBox.shrink();
    final warning = state.mode == E2eeRoomMode.needsUnlock ||
        state.mode == E2eeRoomMode.keyChanged;
    final color = warning ? AppColors.warning : AppColors.textSecondary;
    return Container(
      key: const ValueKey('e2ee-room-notice'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: const Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Icon(
            warning ? Icons.lock_clock_outlined : Icons.lock_open_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notice,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
          if (state.mode == E2eeRoomMode.needsUnlock && onUnlock != null)
            TextButton(onPressed: onUnlock, child: const Text('解锁')),
        ],
      ),
    );
  }
}

/// 输入登录密码。取消返回 null。
Future<String?> showE2eePasswordDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _E2eePasswordDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    ),
  );
}

class _E2eePasswordDialog extends StatefulWidget {
  const _E2eePasswordDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_E2eePasswordDialog> createState() => _E2eePasswordDialogState();
}

class _E2eePasswordDialogState extends State<_E2eePasswordDialog> {
  // 控制器跟着对话框的 State 走：对话框关闭动画期间输入框还在，不能提前释放。
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('e2ee-password-field'),
              controller: _controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: '登录密码'),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 说明"密钥由登录密码保护"的后果，开启和解锁时都给用户看。
const String kE2eePasswordWarning = '加密密钥由你的登录密码保护，服务器无法解开。在设置里修改密码会自动迁移；'
    '但如果忘记密码或密码被管理员重置，之前的加密聊天记录将永久无法解密。';

/// 在这台设备上解锁端到端加密：输密码解开私钥。解不开时可以选择重置密钥
/// （旧的加密记录从此读不了）。返回是否已解锁。
Future<bool> runE2eeUnlockFlow(
  BuildContext context,
  EncryptionService service,
) async {
  final password = await showE2eePasswordDialog(
    context,
    title: '解锁端到端加密',
    message: '输入登录密码，在这台设备上解开你的加密密钥，才能查看和发送加密消息。',
    confirmLabel: '解锁',
  );
  if (password == null || password.isEmpty || !context.mounted) return false;
  try {
    final result = await service.unlockWithPassword(password);
    if (result == E2eeUnlockResult.unlocked) {
      if (context.mounted) _snack(context, '已解锁端到端加密');
      return true;
    }
    if (result == E2eeUnlockResult.noKeys) {
      if (context.mounted) _snack(context, '你还没有开启端到端加密');
      return false;
    }
  } catch (e) {
    if (context.mounted) _snack(context, '解锁失败: $e', error: true);
    return false;
  }
  if (!context.mounted) return false;
  final reset = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('无法解开加密密钥'),
      content: const Text(
        '密码不正确，或者你的加密密钥是用以前的密码保护的（密码被重置过）。\n\n'
        '如果确认密码没错，可以重置加密密钥：之后的私聊会用新密钥加密，'
        '但之前的加密聊天记录将永久无法解密。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('再试一次'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('重置加密密钥'),
        ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (reset == false) return runE2eeUnlockFlow(context, service);
  if (reset != true) return false;
  try {
    await service.resetKeys(password);
    if (context.mounted) _snack(context, '已生成新的加密密钥');
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, '重置失败: $e', error: true);
    return false;
  }
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.error : null,
    ),
  );
}
