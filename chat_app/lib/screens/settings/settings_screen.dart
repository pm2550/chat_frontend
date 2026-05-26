import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/bot_service.dart';
import '../../services/encryption_service.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../profile/profile_edit_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final EncryptionService _encryptionService = EncryptionService();
  final UserProfileService _profileService = UserProfileService();
  bool _e2eeEnabled = false;
  bool _notificationsEnabled = true;
  UserAppSettings _appSettings = const UserAppSettings();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final keysExist = await _encryptionService.checkKeysExist();
    UserAppSettings appSettings = const UserAppSettings();
    try {
      appSettings = await _profileService.getSettings();
    } catch (_) {
      // Settings screen stays usable with defaults if the backend is transiently unavailable.
    }
    setState(() {
      _e2eeEnabled = keysExist;
      _appSettings = appSettings;
      _notificationsEnabled = appSettings.messageNotificationsEnabled;
    });
  }

  Future<void> _saveAppSettings(UserAppSettings settings) async {
    setState(() {
      _appSettings = settings;
      _notificationsEnabled = settings.messageNotificationsEnabled;
    });
    try {
      final saved = await _profileService.updateSettings(settings);
      if (!mounted) return;
      setState(() {
        _appSettings = saved;
        _notificationsEnabled = saved.messageNotificationsEnabled;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('设置保存失败: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openProfileEditor() async {
    final user = _authService.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(user: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktopScaffold();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _buildSettingsList(),
    );
  }

  Widget _buildDesktopScaffold() {
    return Scaffold(
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                PMDesktopHeader(
                  title: '设置中心',
                  subtitle: '管理安全、通知、Bot、账号和合规信息',
                  icon: Icons.settings,
                  actions: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('返回'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: PMDesktopCard(
                          padding: EdgeInsets.zero,
                          child: _buildSettingsList(),
                        ),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 340,
                        child: Column(
                          children: [
                            PMDesktopCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '当前策略',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _DesktopStatusRow(
                                    icon: Icons.lock_outline,
                                    label: '端到端加密',
                                    value: _e2eeEnabled ? '已启用' : '未启用',
                                  ),
                                  const SizedBox(height: 12),
                                  _DesktopStatusRow(
                                    icon: Icons.notifications,
                                    label: '消息通知',
                                    value:
                                        _notificationsEnabled ? '已开启' : '已关闭',
                                  ),
                                  const SizedBox(height: 12),
                                  const _DesktopStatusRow(
                                    icon: Icons.verified_user_outlined,
                                    label: '隐私控制',
                                    value: '已连接后端设置',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            PMDesktopCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    '账户',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _openProfileEditor,
                                    icon: const Icon(Icons.edit, size: 18),
                                    label: const Text('修改个人资料'),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChangePasswordScreen(
                                            authService: _authService,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.password, size: 18),
                                    label: const Text('修改密码'),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
          onChanged: (value) => _saveAppSettings(
            _appSettings.copyWith(messageNotificationsEnabled: value),
          ),
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
            Navigator.push(
                context,
                MaterialPageRoute(
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
          onTap: _openProfileEditor,
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('修改密码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangePasswordScreen(authService: _authService),
              ),
            );
          },
        ),

        // About
        _buildSectionHeader('关于'),
        const ListTile(
          leading: Icon(Icons.info),
          title: Text('版本'),
          subtitle: Text('1.0.0'),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active),
          title: const Text('通知设置'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final updated = await Navigator.push<UserAppSettings>(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationSettingsScreen(
                  initialSettings: _appSettings,
                  profileService: _profileService,
                ),
              ),
            );
            if (updated != null) {
              setState(() {
                _appSettings = updated;
                _notificationsEnabled = updated.messageNotificationsEnabled;
              });
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip),
          title: const Text('隐私设置'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final updated = await Navigator.push<UserAppSettings>(
              context,
              MaterialPageRoute(
                builder: (_) => PrivacySettingsScreen(
                  initialSettings: _appSettings,
                  profileService: _profileService,
                ),
              ),
            );
            if (updated != null) {
              setState(() => _appSettings = updated);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.description),
          title: const Text('隐私政策'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StaticTextScreen(
                title: '隐私政策',
                content:
                    '本应用只在登录、聊天、文件、联系人和机器人功能需要时使用账户资料。消息附件需要登录鉴权访问；端到端加密开启后，后端只保存密文信封。',
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.article),
          title: const Text('用户协议'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StaticTextScreen(
                title: '用户协议',
                content:
                    '请勿上传违法内容、恶意文件或滥用机器人工作区。企业内部部署时，管理员负责账号、数据和第三方模型服务的合规配置。',
              ),
            ),
          ),
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
              final navigator = Navigator.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('确认退出'),
                  content: const Text('确定要退出登录吗？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('退出')),
                  ],
                ),
              );
              if (confirm == true) {
                await _authService.logout();
                if (!mounted) return;
                navigator.pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            child: const Text('退出登录'),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }
}

class _DesktopStatusRow extends StatelessWidget {
  const _DesktopStatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.pixelBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, AuthService? authService})
      : _authService = authService;

  final AuthService? _authService;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final AuthService _authService;
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? AuthService();
  }

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _authService.changePassword(
        oldPassword: _oldController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已修改')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('修改失败: $error'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _oldController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码'),
              validator: (value) =>
                  value == null || value.isEmpty ? '请输入当前密码' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
              validator: (value) {
                if (value == null || value.length < 6) {
                  return '新密码至少 6 位';
                }
                if (value == _oldController.text) {
                  return '新密码不能和当前密码相同';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
              validator: (value) =>
                  value != _newController.text ? '两次输入的新密码不一致' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.initialSettings,
    UserProfileService? profileService,
  }) : _profileService = profileService;

  final UserAppSettings initialSettings;
  final UserProfileService? _profileService;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final UserProfileService _profileService;
  late UserAppSettings _settings;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profileService = widget._profileService ?? UserProfileService();
    _settings = widget.initialSettings;
  }

  Future<void> _save(UserAppSettings settings) async {
    setState(() {
      _settings = settings;
      _isSaving = true;
    });
    try {
      final saved = await _profileService.updateSettings(settings);
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _isSaving = false;
      });
      Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('消息通知'),
            subtitle: const Text('接收离线推送和会话提醒'),
            value: _settings.messageNotificationsEnabled,
            onChanged: _isSaving
                ? null
                : (value) => _save(
                      _settings.copyWith(
                        messageNotificationsEnabled: value,
                      ),
                    ),
            secondary: const Icon(Icons.notifications),
          ),
          SwitchListTile(
            title: const Text('已读回执'),
            subtitle: const Text('允许发送已读状态'),
            value: _settings.readReceiptsEnabled,
            onChanged: _isSaving
                ? null
                : (value) => _save(
                      _settings.copyWith(readReceiptsEnabled: value),
                    ),
            secondary: const Icon(Icons.done_all),
          ),
        ],
      ),
    );
  }
}

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({
    super.key,
    required this.initialSettings,
    UserProfileService? profileService,
  }) : _profileService = profileService;

  final UserAppSettings initialSettings;
  final UserProfileService? _profileService;

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  late final UserProfileService _profileService;
  late UserAppSettings _settings;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profileService = widget._profileService ?? UserProfileService();
    _settings = widget.initialSettings;
  }

  Future<void> _save(UserAppSettings settings) async {
    setState(() {
      _settings = settings;
      _isSaving = true;
    });
    try {
      final saved = await _profileService.updateSettings(settings);
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _isSaving = false;
      });
      Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('显示在线状态'),
            subtitle: const Text('允许联系人看到你的在线/离线状态'),
            value: _settings.showOnlineStatus,
            onChanged: _isSaving
                ? null
                : (value) => _save(
                      _settings.copyWith(showOnlineStatus: value),
                    ),
            secondary: const Icon(Icons.circle),
          ),
          SwitchListTile(
            title: const Text('允许好友请求'),
            subtitle: const Text('关闭后仅能由你主动添加联系人'),
            value: _settings.allowFriendRequests,
            onChanged: _isSaving
                ? null
                : (value) => _save(
                      _settings.copyWith(allowFriendRequests: value),
                    ),
            secondary: const Icon(Icons.person_add_alt_1),
          ),
          SwitchListTile(
            title: const Text('允许私聊'),
            subtitle: const Text('允许好友创建与你的私聊会话'),
            value: _settings.allowDirectMessages,
            onChanged: _isSaving
                ? null
                : (value) => _save(
                      _settings.copyWith(allowDirectMessages: value),
                    ),
            secondary: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      ),
    );
  }
}

class StaticTextScreen extends StatelessWidget {
  const StaticTextScreen({
    super.key,
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(content, style: const TextStyle(height: 1.5)),
      ),
    );
  }
}

// Bot Management Screen (embedded in same file for simplicity)
class BotManagementScreen extends StatefulWidget {
  const BotManagementScreen({super.key, this.botService});

  final BotService? botService;

  @override
  State<BotManagementScreen> createState() => _BotManagementScreenState();
}

class _BotManagementScreenState extends State<BotManagementScreen> {
  late final BotService _botService;
  bool _isLoading = true;
  String? _error;
  List<BotConfig> _bots = [];

  @override
  void initState() {
    super.initState();
    _botService = widget.botService ?? BotService();
    _loadBots();
  }

  Future<void> _loadBots() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final bots = await _botService.getMyBots();
      if (!mounted) return;
      setState(() {
        _bots = bots;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 机器人管理')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateBotDialog(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadBots,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _bots.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.smart_toy, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('还没有创建机器人',
                              style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 8),
                          Text('点击右下角按钮创建',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBots,
                      child: ListView.separated(
                        itemCount: _bots.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final bot = _bots[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.smart_toy),
                            ),
                            title: Text(bot.botName),
                            subtitle: Text(
                              [
                                bot.llmProvider,
                                if (bot.modelName != null &&
                                    bot.modelName!.isNotEmpty)
                                  bot.modelName!,
                              ].join(' · '),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed:
                                  bot.id == null ? null : () => _deleteBot(bot),
                            ),
                          );
                        },
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
                initialValue: selectedProvider,
                items: ['OPENAI', 'CLAUDE', 'DEEPSEEK', 'OLLAMA', 'HERMES']
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final dialogNavigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final created = await _botService.createBot(
                BotConfig(
                  botName: name,
                  llmProvider: selectedProvider,
                  systemPrompt: promptController.text.trim().isEmpty
                      ? null
                      : promptController.text.trim(),
                ),
                apiKey: apiKeyController.text.trim(),
              );
              if (created != null) {
                await _loadBots();
              }
              if (!mounted) return;
              dialogNavigator.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('机器人创建成功')),
              );
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBot(BotConfig bot) async {
    final botId = bot.id;
    if (botId == null) return;
    try {
      await _botService.deleteBot(botId);
      await _loadBots();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
