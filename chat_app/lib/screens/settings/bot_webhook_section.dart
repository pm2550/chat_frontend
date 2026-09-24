import 'package:flutter/material.dart';

import '../../services/bot_service.dart';

/// Bot 外部接入面板里的 Webhook 区域：列出已有订阅、可删除，保存即更新（不会越存越多）。
///
/// 服务端对同一个 bot 的同一作用域只保留一条订阅，这里保存的是"全部房间"作用域；
/// 按房间单独配置的订阅（若有）也会列出来，可以删除。
class BotWebhookSection extends StatefulWidget {
  const BotWebhookSection({
    super.key,
    required this.botService,
    required this.botId,
  });

  final BotService botService;
  final int botId;

  @override
  State<BotWebhookSection> createState() => _BotWebhookSectionState();
}

class _BotWebhookSectionState extends State<BotWebhookSection> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  List<BotWebhook> _webhooks = const [];
  bool _loading = true;
  bool _saving = false;
  final Set<int> _deleting = {};
  String? _error;

  BotWebhook? get _allRoomsWebhook {
    for (final webhook in _webhooks) {
      if (webhook.chatRoomId == null) return webhook;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final webhooks = await widget.botService.listWebhooks(widget.botId);
      if (!mounted) return;
      setState(() {
        _webhooks = webhooks;
        _loading = false;
      });
      final current = _allRoomsWebhook;
      if (current != null && _urlController.text.trim().isEmpty) {
        _urlController.text = current.callbackUrl;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取 Webhook 失败: $error';
      });
    }
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnack('请填写 Callback URL');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.botService.registerWebhook(
        widget.botId,
        callbackUrl: url,
        secret: _secretController.text.trim(),
        eventTypes: 'message',
      );
      _secretController.clear();
      await _load();
      _showSnack('Webhook 已保存');
    } catch (error) {
      _showSnack('保存 Webhook 失败: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(BotWebhook webhook) async {
    setState(() => _deleting.add(webhook.id));
    try {
      await widget.botService.deleteWebhook(webhook.id);
      if (webhook.chatRoomId == null) _urlController.clear();
      await _load();
      _showSnack('Webhook 已删除');
    } catch (error) {
      _showSnack('删除 Webhook 失败: $error');
    } finally {
      if (mounted) setState(() => _deleting.remove(webhook.id));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _describe(BotWebhook webhook) {
    final scope =
        webhook.chatRoomId == null ? '全部房间' : '房间 #${webhook.chatRoomId}';
    final state =
        webhook.active ? '启用中' : '已停用（连续失败 ${webhook.consecutiveFailures} 次）';
    final last = webhook.lastDeliveryStatus == null
        ? '尚未推送'
        : '最近一次响应 ${webhook.lastDeliveryStatus}';
    final secret = webhook.hasSecret ? '已设 secret' : '未设 secret';
    return '$scope · $state · $last · $secret';
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = _allRoomsWebhook != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Webhook', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('有新消息时推送给你的服务（目前只推送聊天消息事件）。'),
        const SizedBox(height: 8),
        if (_loading)
          const LinearProgressIndicator()
        else if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red))
        else if (_webhooks.isEmpty)
          const Text('尚未配置 Webhook')
        else
          for (final webhook in _webhooks)
            ListTile(
              key: ValueKey('bot-webhook-${webhook.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.webhook),
              title: Text(webhook.callbackUrl),
              subtitle: Text(_describe(webhook)),
              trailing: IconButton(
                tooltip: '删除 Webhook',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _deleting.contains(webhook.id)
                    ? null
                    : () => _delete(webhook),
              ),
            ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('bot-webhook-url'),
          controller: _urlController,
          decoration: const InputDecoration(labelText: 'Callback URL'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('bot-webhook-secret'),
          controller: _secretController,
          decoration: InputDecoration(
            labelText: 'Webhook secret',
            helperText: hasExisting ? '留空则沿用原来的 secret' : null,
          ),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          key: const Key('bot-webhook-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: Text(_saving
              ? '保存中...'
              : hasExisting
                  ? '更新 webhook'
                  : '保存 webhook'),
        ),
      ],
    );
  }
}
