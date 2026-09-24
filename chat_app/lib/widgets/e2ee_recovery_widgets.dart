import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../services/file_save.dart' as file_save;

/// 恢复码对话框用到的平台能力：复制、保存文件、打开邮件应用、读本人邮箱。
/// 默认走真实实现，测试里替换掉。
class E2eeRecoveryActions {
  const E2eeRecoveryActions({
    this.saveFile,
    this.openUrl,
    this.selfEmail,
    this.copyText,
  });

  final file_save.FileSaver? saveFile;
  final Future<bool> Function(Uri uri)? openUrl;
  final String? Function()? selfEmail;
  final Future<void> Function(String text)? copyText;

  Future<file_save.FileSaveResult> save({
    required List<int> bytes,
    required String name,
    String? mimeType,
  }) =>
      (saveFile ?? file_save.saveBytesAsFile)(
        bytes: bytes,
        name: name,
        mimeType: mimeType,
      );

  Future<bool> open(Uri uri) =>
      openUrl != null ? openUrl!(uri) : launchUrl(uri);

  String get email =>
      (selfEmail != null ? selfEmail!() : AuthService().currentUser?.email) ??
      '';

  Future<void> copy(String text) => copyText != null
      ? copyText!(text)
      : Clipboard.setData(ClipboardData(text: text));
}

/// 恢复码的后果，设置、生成、发邮件时都给用户看。
const String kE2eeRecoveryWarning =
    '任何能看到这串恢复码的人（例如能读取你邮箱的人），登录你的账号后都能解密你的加密聊天；'
    '登录密码和恢复码都丢了，加密聊天记录将永久无法找回。';

/// 生成一个新恢复码并只显示这一次：可以复制、保存为文件、用自己的邮件应用发给自己。
/// 用户重新输入最后一组确认已保存后，才上传用它包装的私钥（之前取消什么都不改，
/// 重新生成时旧恢复码也还有效）。返回是否已保存。
Future<bool> showE2eeRecoveryCodeSetup(
  BuildContext context,
  EncryptionService service, {
  E2eeRecoveryActions actions = const E2eeRecoveryActions(),
  bool regenerate = false,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RecoveryCodeDialog(
      service: service,
      actions: actions,
      code: E2eeRecoveryCode.generate(),
      regenerate: regenerate,
    ),
  );
  if (saved == true && context.mounted) {
    _snack(context, regenerate ? '新的恢复码已生效，旧恢复码已失效' : '恢复码已设置');
  }
  return saved == true;
}

class _RecoveryCodeDialog extends StatefulWidget {
  const _RecoveryCodeDialog({
    required this.service,
    required this.actions,
    required this.code,
    required this.regenerate,
  });

  final EncryptionService service;
  final E2eeRecoveryActions actions;
  final E2eeRecoveryCode code;
  final bool regenerate;

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  E2eeRecoveryCode get _code => widget.code;
  bool get _confirmed => _code.matchesLastGroup(_confirm.text);

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await widget.actions.copy(_code.formatted);
    if (mounted) _snack(context, '恢复码已复制，请粘贴到安全的地方保存');
  }

  Future<void> _saveFile() async {
    try {
      final result = await widget.actions.save(
        bytes: utf8.encode(E2eeRecoveryMail.fileText(_code)),
        name: E2eeRecoveryMail.fileName,
        mimeType: 'text/plain',
      );
      final message = result.describe(E2eeRecoveryMail.fileName);
      if (message != null && mounted) _snack(context, message);
    } catch (e) {
      if (mounted) _snack(context, '保存失败: $e', error: true);
    }
  }

  Future<void> _email() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _RecoveryEmailDialog(code: _code, actions: widget.actions),
    );
  }

  Future<void> _done() async {
    if (!_confirmed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.saveRecoveryCode(_code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存恢复码失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(widget.regenerate ? '重新生成恢复码' : '保存你的恢复码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '忘记登录密码或密码被管理员重置时，用恢复码可以找回加密聊天记录。'
                '恢复码在这台设备上生成，只显示这一次，服务器不保存、也看不到。',
                style: TextStyle(fontSize: 13.5, height: 1.45),
              ),
              if (widget.regenerate) ...[
                const SizedBox(height: 8),
                const Text(
                  '确认保存后，旧的恢复码立即失效。',
                  style: TextStyle(fontSize: 13.5, color: AppColors.warning),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: SelectableText(
                  _code.formatted,
                  key: const ValueKey('e2ee-recovery-code'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('e2ee-recovery-copy'),
                    onPressed: _copy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('e2ee-recovery-save'),
                    onPressed: _saveFile,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('保存为文件'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('e2ee-recovery-email'),
                    onPressed: _email,
                    icon: const Icon(Icons.email_outlined, size: 16),
                    label: const Text('发送到我的邮箱'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                kE2eeRecoveryWarning,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('e2ee-recovery-confirm-field'),
                controller: _confirm,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: '输入恢复码的最后一组（4 个字符），确认已保存',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _done(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            key: const ValueKey('e2ee-recovery-done'),
            onPressed: _confirmed && !_busy ? _done : null,
            child: Text(_busy ? '正在保存…' : '我已保存'),
          ),
        ],
      ),
    );
  }
}

/// "发送到我的邮箱"：用本机的邮件应用给自己发，收件人默认是账号邮箱，可以改。
class _RecoveryEmailDialog extends StatefulWidget {
  const _RecoveryEmailDialog({required this.code, required this.actions});

  final E2eeRecoveryCode code;
  final E2eeRecoveryActions actions;

  @override
  State<_RecoveryEmailDialog> createState() => _RecoveryEmailDialogState();
}

class _RecoveryEmailDialogState extends State<_RecoveryEmailDialog> {
  late final TextEditingController _to = TextEditingController(
    text: widget.actions.email,
  );
  String? _error;

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final Uri uri;
    try {
      uri = E2eeRecoveryMail.buildUri(to: _to.text, code: widget.code);
    } on FormatException {
      setState(() => _error = '邮箱地址格式不正确');
      return;
    }
    var opened = false;
    try {
      opened = await widget.actions.open(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      setState(() => _error = '没有找到可用的邮件应用，请改用"复制"或"保存为文件"');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发送到我的邮箱'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '将打开这台设备上的邮件应用，写好一封发给你自己的邮件，由你自己点发送。'
              'PM chat 的服务器不会经手这封邮件。',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('e2ee-recovery-email-field'),
              controller: _to,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: '收件人', errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            const Text(
              '任何能读取这个邮箱的人，登录你的账号后都能解密你的加密聊天。'
              '请确认这是只有你能看到的邮箱。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.error,
              ),
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
          key: const ValueKey('e2ee-recovery-email-open'),
          onPressed: _open,
          child: const Text('打开邮件应用'),
        ),
      ],
    );
  }
}

/// 用恢复码找回：输入恢复码在本机解开私钥（恢复码不发给服务器），再用现在的登录密码
/// 重新包装上传，之后各设备用现在的密码都能解锁。[password] 是刚输过的登录密码
/// （从解锁失败进来时），有就不再问。返回是否已找回。
Future<bool> runE2eeRecoveryFlow(
  BuildContext context,
  EncryptionService service, {
  String? password,
}) async {
  final result = await showDialog<E2eeRecoveryResult>(
    context: context,
    builder: (context) =>
        _RecoveryEntryDialog(service: service, password: password),
  );
  if (result == null || !context.mounted) return false;
  _snack(
    context,
    result == E2eeRecoveryResult.restored
        ? '已用恢复码找回加密密钥，并改用现在的登录密码保护'
        : '已用恢复码在这台设备上解锁。请修改一次登录密码，其他设备才能用新密码解锁',
  );
  return true;
}

class _RecoveryEntryDialog extends StatefulWidget {
  const _RecoveryEntryDialog({required this.service, this.password});

  final EncryptionService service;
  final String? password;

  @override
  State<_RecoveryEntryDialog> createState() => _RecoveryEntryDialogState();
}

class _RecoveryEntryDialogState extends State<_RecoveryEntryDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  late bool _askPassword = widget.password == null;

  /// 恢复码已经解开了私钥，剩下的只是用登录密码重新包装。
  bool _codeAccepted = false;
  bool _busy = false;
  String? _codeError;
  String? _passwordError;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _askPassword ? _password.text : widget.password!;
    if (password.isEmpty) {
      setState(() => _passwordError = '请输入现在的登录密码');
      return;
    }
    setState(() {
      _busy = true;
      _codeError = null;
      _passwordError = null;
    });
    try {
      final E2eeRecoveryResult result;
      if (_codeAccepted) {
        await widget.service.rewrapWithCurrentPassword(password);
        result = E2eeRecoveryResult.restored;
      } else {
        result = await widget.service.recoverWithCode(
          _code.text,
          password: password,
        );
      }
      if (mounted) Navigator.of(context).pop(result);
      return;
    } on E2eeWrongPasswordException {
      // 恢复码没问题（私钥已在本机解开），只是登录密码不对。
      _codeAccepted = true;
      _askPassword = true;
      _passwordError = '登录密码不正确（恢复码已验证）';
    } on E2eeRecoveryCodeFormatException catch (e) {
      _codeError = e.message;
    } on E2eeWrongRecoveryCodeException catch (e) {
      _codeError = e.message;
    } catch (e) {
      _codeError = '找回失败: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('用恢复码找回'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入你保存的恢复码。恢复码只在这台设备上用来解开加密密钥，不会发送给服务器；'
              '解开后会改用你现在的登录密码保护，之后各设备用现在的密码就能解锁。',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('e2ee-recovery-input'),
              controller: _code,
              enabled: !_codeAccepted,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: '恢复码',
                hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                errorText: _codeError,
                errorMaxLines: 3,
              ),
            ),
            if (_askPassword) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('e2ee-recovery-password-field'),
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '现在的登录密码',
                  errorText: _passwordError,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('e2ee-recovery-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '正在找回…' : '找回'),
        ),
      ],
    );
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
