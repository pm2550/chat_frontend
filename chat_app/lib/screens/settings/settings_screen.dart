import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/encryption_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final EncryptionService _encryptionService = EncryptionService();
  bool _e2eeEnabled = false;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final keysExist = await _encryptionService.checkKeysExist();
    setState(() {
      _e2eeEnabled = keysExist;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // Privacy & Security
          _buildSectionHeader('隐私与安全'),
          SwitchListTile(
            title: const Text('端到端加密'),
            subtitle: Text(_e2eeEnabled ? '已启用' : '未启用'),
            value: _e2eeEnabled,
            onChanged: (value) async {
              if (value) {
                final success = await _encryptionService.generateAndUploadKeys();
                setState(() => _e2eeEnabled = success);
                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('加密密钥已生成并上传')),
                  );
                }
              }
            },
            secondary: const Icon(Icons.lock),
          ),
          const ListTile(
            leading: Icon(Icons.timer),
            title: Text('阅后即焚默认时间'),
            subtitle: Text('关闭'),
            trailing: Icon(Icons.chevron_right),
          ),

          // Notifications
          _buildSectionHeader('通知'),
          SwitchListTile(
            title: const Text('消息通知'),
            value: _notificationsEnabled,
            onChanged: (value) => setState(() => _notificationsEnabled = value),
            secondary: const Icon(Icons.notifications),
          ),

          // LLM Bot
          _buildSectionHeader('AI 机器人'),
          ListTile(
            leading: const Icon(Icons.smart_toy),
            title: const Text('管理机器人'),
            subtitle: const Text('创建和管理AI聊天机器人'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const BotManagementScreen(),
              ));
            },
          ),

          // Account
          _buildSectionHeader('账户'),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('修改个人资料'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/profile/edit'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('修改密码'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {/* TODO */},
          ),

          // About
          _buildSectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('版本'),
            subtitle: Text('1.0.0'),
          ),
          const ListTile(
            leading: Icon(Icons.description),
            title: Text('隐私政策'),
            trailing: Icon(Icons.chevron_right),
          ),
          const ListTile(
            leading: Icon(Icons.article),
            title: Text('用户协议'),
            trailing: Icon(Icons.chevron_right),
          ),

          // Logout
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确认退出'),
                    content: const Text('确定要退出登录吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await _authService.logout();
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                }
              },
              child: const Text('退出登录'),
            ),
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

// Bot Management Screen (embedded in same file for simplicity)
class BotManagementScreen extends StatefulWidget {
  const BotManagementScreen({super.key});

  @override
  State<BotManagementScreen> createState() => _BotManagementScreenState();
}

class _BotManagementScreenState extends State<BotManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 机器人管理')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateBotDialog(),
        child: const Icon(Icons.add),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_toy, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('还没有创建机器人', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text('点击右下角按钮创建', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _showCreateBotDialog() {
    final nameController = TextEditingController();
    final promptController = TextEditingController();
    final apiKeyController = TextEditingController();
    String selectedProvider = 'OPENAI';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建AI机器人'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '机器人名称'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedProvider,
                items: ['OPENAI', 'CLAUDE', 'DEEPSEEK', 'OLLAMA']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => selectedProvider = v ?? 'OPENAI',
                decoration: const InputDecoration(labelText: 'LLM 提供者'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: apiKeyController,
                decoration: const InputDecoration(labelText: 'API Key (可选)'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: promptController,
                decoration: const InputDecoration(labelText: '系统提示词'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              // TODO: Call BotService.createBot()
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('机器人创建成功')),
              );
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}
