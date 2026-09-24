import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/contact_data_service.dart';
import '../../services/friend_code.dart';
import 'qr_scanner_page.dart';

typedef QrScanLauncher = Future<String?> Function(BuildContext context);

/// 扫码 / 输入用户名加好友。
///
/// 只做**精确**匹配：二维码里的用户名、或手动输入的完整用户名（纯数字时也可
/// 以是用户 ID）。找到后先展示对方的头像和名字，由用户确认后才发送好友请求。
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({
    super.key,
    this.initialCode,
    this.contactService,
    this.authService,
    this.scanner,
  });

  /// 深链接 `/add/<用户名>` 或扫码结果，打开后立即查找。
  final String? initialCode;
  final ContactDataService? contactService;
  final AuthService? authService;

  /// 打开摄像头扫码；为 null 时在 Android/iOS 用 [QrScannerPage]，
  /// 其它平台不显示扫码入口。
  final QrScanLauncher? scanner;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

enum _LookupStatus { idle, loading, found, notFound, invalid, error }

class _AddFriendScreenState extends State<AddFriendScreen> {
  late final ContactDataService _contactService;
  late final AuthService _authService;
  final TextEditingController _controller = TextEditingController();

  _LookupStatus _status = _LookupStatus.idle;
  User? _found;
  String _query = '';
  String? _error;
  bool _isFriend = false;
  bool _requestPending = false;
  bool _sending = false;
  int _lookupGeneration = 0;

  QrScanLauncher? get _scanner =>
      widget.scanner ?? (isQrScanSupported ? QrScannerPage.open : null);

  @override
  void initState() {
    super.initState();
    _contactService = widget.contactService ?? ContactDataService();
    _authService = widget.authService ?? AuthService();
    final initial = widget.initialCode?.trim();
    if (initial != null && initial.isNotEmpty) {
      final target = FriendCode.parse(initial);
      _controller.text = target?.username ?? initial;
      unawaited(_lookup(initial));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final scanner = _scanner;
    if (scanner == null) return;
    final raw = await scanner(context);
    if (raw == null || !mounted) return;
    final target = FriendCode.parse(raw);
    if (target?.username != null) _controller.text = target!.username!;
    await _lookup(raw);
  }

  Future<void> _lookup(String raw) async {
    final generation = ++_lookupGeneration;
    final target = FriendCode.parse(raw);
    if (target == null) {
      setState(() {
        _status = _LookupStatus.invalid;
        _found = null;
        _query = raw.trim();
      });
      return;
    }
    setState(() {
      _status = _LookupStatus.loading;
      _found = null;
      _error = null;
      _query = target.username ?? target.id ?? raw.trim();
    });
    try {
      var user = target.username == null
          ? null
          : await _contactService.lookupUser(username: target.username);
      if (user == null && target.id != null) {
        user = await _contactService.lookupUser(id: target.id);
      }
      if (!mounted || generation != _lookupGeneration) return;
      if (user == null) {
        setState(() => _status = _LookupStatus.notFound);
        return;
      }
      final relation = await _relationTo(user.id);
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _found = user;
        _isFriend = relation.$1;
        _requestPending = relation.$2;
        _status = _LookupStatus.found;
      });
    } catch (e) {
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _status = _LookupStatus.error;
        _error = e.toString();
      });
    }
  }

  /// (已是好友, 已发送过待处理的请求)
  Future<(bool, bool)> _relationTo(String userId) async {
    try {
      final friends = await _contactService.getFriends();
      if (friends.any((friend) => friend.id == userId)) return (true, false);
      final sent = await _contactService.getSentFriendRequests();
      final pending = sent.any((request) =>
          request.status.toUpperCase() == 'PENDING' &&
          (request.friend.id == userId || request.user.id == userId));
      return (false, pending);
    } catch (_) {
      // 关系未知时照常允许发送；后端会拒绝重复请求并给出原因。
      return (false, false);
    }
  }

  Future<void> _sendRequest() async {
    final user = _found;
    if (user == null || _sending) return;
    setState(() => _sending = true);
    try {
      final request = await _contactService.sendFriendRequest(user.id);
      if (!mounted) return;
      final accepted = request.status.toUpperCase() == 'ACCEPTED';
      setState(() {
        _sending = false;
        _isFriend = accepted;
        _requestPending = !accepted;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepted
              ? '已添加 ${_displayName(user)} 为好友'
              : '已向 ${_displayName(user)} 发送好友请求'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showMyCode() {
    final me = _authService.currentUser;
    if (me == null) return;
    unawaited(showMyFriendCode(context, me));
  }

  @override
  Widget build(BuildContext context) {
    final scanner = _scanner;
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加好友'),
        actions: [
          if (_authService.currentUser != null)
            TextButton.icon(
              onPressed: _showMyCode,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('我的二维码'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(PMSpacing.l),
        children: [
          if (scanner != null) ...[
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫一扫好友的二维码'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: PMSpacing.l),
          ],
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: _lookup,
            decoration: InputDecoration(
              labelText: '对方的用户名',
              hintText: '输入完整的用户名，或粘贴加好友链接',
              helperText: '只查找完全一致的用户名，不会模糊匹配',
              prefixIcon: const Icon(Icons.alternate_email),
              suffixIcon: IconButton(
                tooltip: '查找',
                icon: const Icon(Icons.search),
                onPressed: () => _lookup(_controller.text),
              ),
            ),
          ),
          const SizedBox(height: PMSpacing.l),
          _buildResult(),
        ],
      ),
    );
  }

  Widget _buildResult() {
    switch (_status) {
      case _LookupStatus.idle:
        return const SizedBox.shrink();
      case _LookupStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case _LookupStatus.invalid:
        return _message('无法识别：请扫描 PM chat 的加好友二维码，或输入完整的用户名');
      case _LookupStatus.notFound:
        return _message('没有找到用户名为“$_query”的用户');
      case _LookupStatus.error:
        return _message('查找失败: $_error', color: AppColors.error);
      case _LookupStatus.found:
        return _buildFoundCard(_found!);
    }
  }

  Widget _message(String text, {Color color = AppColors.textSecondary}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PMSpacing.m),
      child: Text(text, style: TextStyle(color: color, height: 1.45)),
    );
  }

  Widget _buildFoundCard(User user) {
    final isSelf = user.id == _authService.currentUser?.id;
    final Widget action;
    if (isSelf) {
      action = const Text(
        '这是你自己',
        style: TextStyle(color: AppColors.textSecondary),
      );
    } else if (_isFriend) {
      action = const PMChip(
        label: '已是好友',
        icon: Icons.check_circle,
        selected: true,
        color: AppColors.success,
      );
    } else if (_requestPending) {
      action = const PMChip(
        label: '已发送好友请求',
        icon: Icons.hourglass_top,
        selected: true,
        color: AppColors.warning,
      );
    } else {
      action = FilledButton.icon(
        key: const ValueKey('add-friend-send-request'),
        onPressed: _sending ? null : _sendRequest,
        icon: _sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.person_add_alt_1),
        label: const Text('发送好友请求'),
      );
    }

    return PMCard(
      key: const ValueKey('add-friend-result'),
      child: Column(
        children: [
          PMUserAvatar(user: user, size: 72),
          const SizedBox(height: PMSpacing.m),
          Text(
            _displayName(user),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: PMSpacing.xs),
          Text(
            '@${user.username}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (user.title?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: PMSpacing.xs),
            PMTitleBadge(
              title: user.title,
              color: user.titleColor,
              effect: user.titleEffect,
            ),
          ],
          if (user.bio?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: PMSpacing.s),
            Text(
              user.bio!.trim(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: PMSpacing.l),
          action,
        ],
      ),
    );
  }
}

String _displayName(User user) =>
    user.displayName.trim().isNotEmpty ? user.displayName : user.username;

/// “我的二维码”：二维码内容是 [FriendCode.linkFor] 生成的加好友链接。
Future<void> showMyFriendCode(BuildContext context, User me) {
  final link = FriendCode.linkFor(me.username);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const PMDialogHeader(title: '我的二维码', showHandle: false),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PMUserAvatar(user: me, size: 56),
              const SizedBox(height: PMSpacing.s),
              Text(
                _displayName(me),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              Text(
                '@${me.username}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: PMSpacing.m),
              Container(
                key: const ValueKey('my-friend-qr'),
                padding: const EdgeInsets.all(PMSpacing.s),
                color: Colors.white,
                child: QrImageView(
                  data: link,
                  size: 220,
                  backgroundColor: Colors.white,
                  semanticsLabel: '加好友二维码',
                ),
              ),
              const SizedBox(height: PMSpacing.xs),
              SelectableText(
                link,
                key: const ValueKey('my-friend-link'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: PMSpacing.s),
              const Text(
                '让对方用 PM chat 扫一扫，或用手机相机扫码打开网页版加你为好友',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('加好友链接已复制')),
            );
          },
          icon: const Icon(Icons.link),
          label: const Text('复制链接'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}
