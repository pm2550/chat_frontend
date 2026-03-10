import 'package:flutter/material.dart';
import '../../services/anonymous_service.dart';
import '../../services/bot_service.dart';

class ChatRoomSettingsScreen extends StatefulWidget {
  final int chatRoomId;
  final String chatRoomName;
  final bool isAdmin;
  final bool isGroup;

  const ChatRoomSettingsScreen({
    super.key,
    required this.chatRoomId,
    required this.chatRoomName,
    this.isAdmin = false,
    this.isGroup = false,
  });

  @override
  State<ChatRoomSettingsScreen> createState() => _ChatRoomSettingsScreenState();
}

class _ChatRoomSettingsScreenState extends State<ChatRoomSettingsScreen> {
  final AnonymousService _anonymousService = AnonymousService();
  final BotService _botService = BotService();
  bool _anonymousEnabled = false;
  List<BotConfig> _bots = [];

  @override
  void initState() {
    super.initState();
    _loadBots();
  }

  Future<void> _loadBots() async {
    final bots = await _botService.getBotsInRoom(widget.chatRoomId);
    setState(() => _bots = bots);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chatRoomName)),
      body: ListView(
        children: [
          // Group info
          _buildSectionHeader('群组信息'),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.group)),
            title: Text(widget.chatRoomName),
            subtitle: const Text('点击修改群名称'),
            trailing: const Icon(Icons.chevron_right),
          ),
          const ListTile(
            leading: Icon(Icons.people),
            title: Text('成员管理'),
            trailing: Icon(Icons.chevron_right),
          ),

          if (widget.isGroup) ...[
            // Anonymous chat
            _buildSectionHeader('匿名聊天'),
            SwitchListTile(
              title: const Text('允许匿名聊天'),
              subtitle: const Text('开启后群成员可匿名发言'),
              value: _anonymousEnabled,
              onChanged: widget.isAdmin ? (value) async {
                final success = await _anonymousService.toggleAnonymous(
                    widget.chatRoomId, value);
                if (success) {
                  setState(() => _anonymousEnabled = value);
                }
              } : null,
              secondary: const Icon(Icons.masks),
            ),

            // Bots
            _buildSectionHeader('AI 机器人'),
            ..._bots.map((bot) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue[100],
                child: const Icon(Icons.smart_toy, color: Colors.blue),
              ),
              title: Text(bot.botName),
              subtitle: Text(bot.llmProvider),
              trailing: widget.isAdmin
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () async {
                        await _botService.removeBotFromRoom(
                            widget.chatRoomId, bot.id!);
                        _loadBots();
                      },
                    )
                  : null,
            )),
            if (widget.isAdmin)
              ListTile(
                leading: const Icon(Icons.add_circle, color: Colors.green),
                title: const Text('添加机器人'),
                onTap: () {/* TODO: Show bot picker */},
              ),
          ],

          // Notification settings
          _buildSectionHeader('通知设置'),
          SwitchListTile(
            title: const Text('消息免打扰'),
            value: false,
            onChanged: (value) {},
            secondary: const Icon(Icons.notifications_off),
          ),
          SwitchListTile(
            title: const Text('置顶聊天'),
            value: false,
            onChanged: (value) {},
            secondary: const Icon(Icons.push_pin),
          ),

          // Danger zone
          _buildSectionHeader('操作'),
          ListTile(
            leading: const Icon(Icons.cleaning_services, color: Colors.orange),
            title: const Text('清空聊天记录'),
            onTap: () {/* TODO */},
          ),
          if (!widget.isGroup || !widget.isAdmin)
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text('退出群聊'),
              onTap: () {/* TODO */},
            ),
          if (widget.isAdmin)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('解散群聊'),
              onTap: () {/* TODO */},
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title, style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      )),
    );
  }
}
