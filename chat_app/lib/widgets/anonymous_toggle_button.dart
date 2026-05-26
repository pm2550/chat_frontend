import 'package:flutter/material.dart';
import '../services/anonymous_service.dart';

class AnonymousToggleButton extends StatefulWidget {
  final int chatRoomId;
  final bool anonymousEnabled;
  final ValueChanged<AnonymousIdentity?> onAnonymousChanged;

  const AnonymousToggleButton({
    super.key,
    required this.chatRoomId,
    required this.anonymousEnabled,
    required this.onAnonymousChanged,
  });

  @override
  State<AnonymousToggleButton> createState() => _AnonymousToggleButtonState();
}

class _AnonymousToggleButtonState extends State<AnonymousToggleButton> {
  final AnonymousService _anonymousService = AnonymousService();
  AnonymousIdentity? _currentIdentity;
  bool _isAnonymous = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.anonymousEnabled) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _isAnonymous ? Icons.masks : Icons.masks_outlined,
            color: _isAnonymous ? Colors.purple : Colors.grey,
          ),
          tooltip: _isAnonymous ? '退出匿名' : '匿名发言',
          onPressed: () async {
            if (_isAnonymous) {
              setState(() {
                _isAnonymous = false;
                _currentIdentity = null;
              });
              widget.onAnonymousChanged(null);
            } else {
              final identity =
                  await _anonymousService.enterAnonymousMode(widget.chatRoomId);
              if (identity != null) {
                setState(() {
                  _isAnonymous = true;
                  _currentIdentity = identity;
                });
                widget.onAnonymousChanged(identity);
              }
            }
          },
        ),
        if (_isAnonymous && _currentIdentity != null)
          GestureDetector(
            onTap: _currentIdentity!.customNameUsed
                ? null
                : () => _showRenameDialog(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.masks, size: 14, color: Colors.purple),
                  const SizedBox(width: 4),
                  Text(
                    _currentIdentity!.anonymousName,
                    style: const TextStyle(fontSize: 12, color: Colors.purple),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改匿名昵称'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('每天只能改名一次哦~',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入新昵称 (2-20字)',
                border: OutlineInputBorder(),
              ),
              maxLength: 20,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.length >= 2) {
                final result = await _anonymousService.renameAnonymous(
                    widget.chatRoomId, controller.text);
                if (!context.mounted || !ctx.mounted) return;
                if (result != null) {
                  setState(() => _currentIdentity = result);
                  widget.onAnonymousChanged(result);
                }
                Navigator.pop(ctx);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
