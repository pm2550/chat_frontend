import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/auth_service.dart';
import '../../services/bot_service.dart';
import '../../services/encryption_service.dart';
import '../../services/user_profile_service.dart';
import '../../services/web_push_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../profile/profile_edit_screen.dart';
import 'chat_preferences_screen.dart';
import 'points_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final EncryptionService _encryptionService = EncryptionService();
  final UserProfileService _profileService = UserProfileService();
  final TextEditingController _searchController = TextEditingController();
  bool _e2eeEnabled = false;
  bool _isGeneratingE2ee = false;
  bool _notificationsEnabled = true;
  UserAppSettings _appSettings = const UserAppSettings();
  String _settingsQuery = '';
  String _appVersionLabel = '读取中';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final buildNumber = info.buildNumber.trim();
      final label = buildNumber.isEmpty ? version : '$version ($buildNumber)';
      if (!mounted) return;
      setState(() => _appVersionLabel = label);
    } catch (_) {
      if (!mounted) return;
      setState(() => _appVersionLabel = '未知');
    }
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

  Future<void> _handleE2eeChanged(bool value) async {
    if (!value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂不支持在客户端删除已生成的端到端加密密钥')),
      );
      return;
    }
    if (_e2eeEnabled || _isGeneratingE2ee) return;

    setState(() => _isGeneratingE2ee = true);
    try {
      final success = await _encryptionService.generateAndUploadKeys();
      if (!mounted) return;
      setState(() {
        _e2eeEnabled = success;
        _isGeneratingE2ee = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '加密密钥已生成并上传' : '加密密钥生成失败'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isGeneratingE2ee = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('加密密钥生成失败: $error'),
          backgroundColor: AppColors.error,
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
      appBar: AppBar(title: const Text('设置中心')),
      body: _buildSettingsList(showMobilePolicy: true),
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
                  subtitle: '管理隐私安全、通知、账号和合规信息',
                  icon: Icons.settings,
                  actions: [
                    PMButton(
                      label: '返回',
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.of(context).maybePop(),
                      variant: PMButtonVariant.secondary,
                      compact: true,
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
                        width: 260,
                        child: _buildPolicyPanel(),
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

  Widget _buildSettingsList({bool showMobilePolicy = false}) {
    final sections = [
      _buildPrivacySection(),
      _buildNotificationSection(),
      _buildAccountSection(),
      _buildAboutSection(),
      _buildDangerSection(),
    ].whereType<Widget>().toList();

    return ListView(
      padding: const EdgeInsets.all(PMSpacing.xl),
      children: [
        _buildSettingsSearchBox(),
        if (_isGeneratingE2ee) ...[
          const SizedBox(height: PMSpacing.l),
          const PMProgressStrip(label: '正在生成端到端加密密钥...'),
        ],
        const SizedBox(height: PMSpacing.l),
        if (sections.isEmpty)
          PMEmptyState(
            icon: Icons.search_off,
            title: '没有找到相关设置',
            subtitle: '换一个关键词试试，例如「通知」「隐私」或「密码」。',
            variant: EmptyStateVariant.muted,
            action: PMButton(
              label: '清空搜索',
              icon: Icons.close,
              onPressed: () {
                _searchController.clear();
                setState(() => _settingsQuery = '');
              },
              variant: PMButtonVariant.secondary,
            ),
          )
        else
          for (var i = 0; i < sections.length; i++) ...[
            sections[i],
            if (i != sections.length - 1) const SizedBox(height: PMSpacing.l),
          ],
        if (showMobilePolicy) ...[
          const SizedBox(height: PMSpacing.l),
          _buildMobilePolicyCard(),
        ],
        const SizedBox(height: PMSpacing.xl),
      ],
    );
  }

  Widget? _buildPrivacySection() {
    final rows = <Widget>[
      if (_matchesSetting('端到端加密', ['密钥', 'e2ee', '隐私', '安全']))
        PMListRow(
          leading: _settingsIcon(Icons.lock_outline, AppColors.primary),
          title: const Text('端到端加密'),
          subtitle: Text(_e2eeEnabled ? '已启用，新消息会使用本地密钥保护' : '为新消息生成并上传公钥'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_e2eeEnabled)
                const PMChip(
                  label: '已启用',
                  icon: Icons.verified_user_outlined,
                  selected: true,
                  color: AppColors.success,
                ),
              if (_e2eeEnabled) const SizedBox(width: PMSpacing.s),
              Switch(
                value: _e2eeEnabled,
                onChanged: _isGeneratingE2ee ? null : _handleE2eeChanged,
              ),
            ],
          ),
        ),
      if (_matchesSetting('显示在线状态', ['隐私', '在线', '状态']))
        PMListRow(
          leading: _settingsIcon(Icons.circle, AppColors.success),
          title: const Text('显示在线状态'),
          subtitle: const Text('允许联系人看到你的在线、离开或忙碌状态'),
          trailing: Switch(
            value: _appSettings.showOnlineStatus,
            onChanged: (value) => _saveAppSettings(
              _appSettings.copyWith(showOnlineStatus: value),
            ),
          ),
        ),
      if (_matchesSetting('允许好友请求', ['隐私', '联系人']))
        PMListRow(
          leading:
              _settingsIcon(Icons.person_add_alt_1, AppColors.secondaryDark),
          title: const Text('允许好友请求'),
          subtitle: const Text('关闭后仅能由你主动添加联系人'),
          trailing: Switch(
            value: _appSettings.allowFriendRequests,
            onChanged: (value) => _saveAppSettings(
              _appSettings.copyWith(allowFriendRequests: value),
            ),
          ),
        ),
      if (_matchesSetting('允许私聊', ['隐私', '聊天']))
        PMListRow(
          leading:
              _settingsIcon(Icons.chat_bubble_outline, AppColors.primaryDark),
          title: const Text('允许私聊'),
          subtitle: const Text('允许好友创建与你的私聊会话'),
          trailing: Switch(
            value: _appSettings.allowDirectMessages,
            onChanged: (value) => _saveAppSettings(
              _appSettings.copyWith(allowDirectMessages: value),
            ),
          ),
        ),
      if (_matchesSetting('阅后即焚默认时间', ['安全', '计时', '消息']))
        PMListRow(
          leading: _settingsIcon(Icons.timer_outlined, AppColors.warning),
          title: const Text('阅后即焚默认时间'),
          subtitle: const Text('关闭'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        ),
    ];
    return _sectionOrNull(
      title: '隐私安全',
      subtitle: '加密、在线状态和联系人可见性',
      rows: rows,
    );
  }

  Widget? _buildNotificationSection() {
    final rows = <Widget>[
      if (_matchesSetting('消息通知', ['通知', '提醒', '推送']))
        PMListRow(
          leading:
              _settingsIcon(Icons.notifications_outlined, AppColors.primary),
          title: const Text('消息通知'),
          subtitle: const Text('接收离线推送和会话提醒'),
          trailing: Switch(
            value: _notificationsEnabled,
            onChanged: (value) => _saveAppSettings(
              _appSettings.copyWith(messageNotificationsEnabled: value),
            ),
          ),
        ),
      if (_matchesSetting('已读回执', ['通知', '回执', '已读']))
        PMListRow(
          leading: _settingsIcon(Icons.done_all, AppColors.secondaryDark),
          title: const Text('已读回执'),
          subtitle: const Text('允许发送已读状态'),
          trailing: Switch(
            value: _appSettings.readReceiptsEnabled,
            onChanged: (value) => _saveAppSettings(
              _appSettings.copyWith(readReceiptsEnabled: value),
            ),
          ),
        ),
      if (_matchesSetting('通知设置', ['通知', '高级']))
        PMListRow(
          leading: _settingsIcon(
              Icons.notifications_active_outlined, AppColors.accent),
          title: const Text('通知设置'),
          subtitle: const Text('进入完整通知设置页'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
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
    ];
    return _sectionOrNull(
      title: '通知',
      subtitle: '消息提醒、已读回执和推送偏好',
      rows: rows,
    );
  }

  Widget? _buildAccountSection() {
    final rows = <Widget>[
      if (_matchesSetting('修改个人资料', ['账号', '头像', '资料']))
        PMListRow(
          leading: _settingsIcon(Icons.person_outline, AppColors.primary),
          title: const Text('修改个人资料'),
          subtitle: const Text('头像、昵称、简介和联系方式'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: _openProfileEditor,
        ),
      if (_matchesSetting('聊天偏好', ['账号', '外观', '背景', '头像框', '气泡']))
        PMListRow(
          leading: _settingsIcon(Icons.palette_outlined, AppColors.accent),
          title: const Text('聊天偏好'),
          subtitle: const Text('聊天背景、头像框和自己发送的气泡样式'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () async {
            final updated = await Navigator.push<UserAppSettings>(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPreferencesScreen(
                  initialSettings: _appSettings,
                  profileService: _profileService,
                ),
              ),
            );
            if (updated != null) {
              setState(() => _appSettings = updated);
            } else {
              await _loadSettings();
            }
          },
        ),
      if (_matchesSetting('我的积分', ['账号', '积分', '点数', '兑换码', 'AI']))
        PMListRow(
          leading: _settingsIcon(Icons.toll, AppColors.secondary),
          title: const Text('我的积分'),
          subtitle: const Text('查看免费额度、付费积分、兑换码和账本记录'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PointsScreen()),
            );
          },
        ),
      if (_matchesSetting('修改密码', ['账号', '安全', '登录']))
        PMListRow(
          leading:
              _settingsIcon(Icons.password_outlined, AppColors.primaryDark),
          title: const Text('修改密码'),
          subtitle: const Text('更新当前账号的登录密码'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangePasswordScreen(authService: _authService),
              ),
            );
          },
        ),
      if (_matchesSetting('管理机器人', ['AI', 'Bot', '机器人', '账号']))
        PMListRow(
          leading:
              _settingsIcon(Icons.smart_toy_outlined, AppColors.secondaryDark),
          title: const Text('管理机器人'),
          subtitle: const Text('创建和管理 AI 聊天机器人'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BotManagementScreen()),
            );
          },
        ),
      if (_matchesSetting('隐私设置', ['账号', '隐私', '高级']))
        PMListRow(
          leading: _settingsIcon(Icons.privacy_tip_outlined, AppColors.warning),
          title: const Text('隐私设置'),
          subtitle: const Text('进入完整隐私设置页'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
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
    ];
    return _sectionOrNull(
      title: '账号',
      subtitle: '个人资料、密码和机器人入口',
      rows: rows,
    );
  }

  Widget? _buildAboutSection() {
    final rows = <Widget>[
      if (_matchesSetting('版本', ['关于']))
        PMListRow(
          leading: _settingsIcon(Icons.info_outline, AppColors.primary),
          title: const Text('版本'),
          subtitle: Text(_appVersionLabel),
        ),
      if (_matchesSetting('隐私政策', ['关于', '合规']))
        PMListRow(
          leading: _settingsIcon(
              Icons.description_outlined, AppColors.secondaryDark),
          title: const Text('隐私政策'),
          subtitle: const Text('查看数据使用和附件鉴权说明'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
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
      if (_matchesSetting('用户协议', ['关于', '协议']))
        PMListRow(
          leading: _settingsIcon(Icons.article_outlined, AppColors.accent),
          title: const Text('用户协议'),
          subtitle: const Text('查看内部部署和使用边界'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
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
    ];
    return _sectionOrNull(
      title: '关于',
      subtitle: '版本、协议和合规文档',
      rows: rows,
    );
  }

  Widget? _buildDangerSection() {
    final rows = <Widget>[
      if (_matchesSetting('退出登录', ['危险', '账号']))
        PMListRow(
          leading: _settingsIcon(Icons.logout, AppColors.error),
          title: const Text(
            '退出登录',
            style: TextStyle(color: AppColors.error),
          ),
          subtitle: const Text('清除本机登录态并返回登录页'),
          trailing: const Icon(Icons.chevron_right, color: AppColors.error),
          onTap: _confirmLogout,
        ),
    ];
    return _sectionOrNull(
      title: '危险操作',
      subtitle: '这些操作会影响当前登录会话',
      rows: rows,
    );
  }

  Widget? _sectionOrNull({
    required String title,
    required String subtitle,
    required List<Widget> rows,
  }) {
    if (rows.isEmpty) return null;
    return PMSectionCard(title: title, subtitle: subtitle, children: rows);
  }

  Widget _buildSettingsSearchBox() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _settingsQuery = value.trim()),
      decoration: InputDecoration(
        hintText: '搜索设置项',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _settingsQuery.isEmpty
            ? null
            : IconButton(
                tooltip: '清空搜索',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _settingsQuery = '');
                },
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }

  Widget _settingsIcon(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PMRadius.m),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  bool _matchesSetting(String title, List<String> keywords) {
    final query = _settingsQuery.toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [title, ...keywords].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  Widget _buildPolicyPanel() {
    return PMCard(
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
          const SizedBox(height: PMSpacing.m),
          _DesktopStatusRow(
            icon: Icons.lock_outline,
            label: '端到端加密',
            value: _e2eeEnabled ? '已启用' : '未启用',
          ),
          const SizedBox(height: PMSpacing.m),
          _DesktopStatusRow(
            icon: Icons.notifications_outlined,
            label: '消息通知',
            value: _notificationsEnabled ? '已开启' : '已关闭',
          ),
          const SizedBox(height: PMSpacing.m),
          _DesktopStatusRow(
            icon: Icons.done_all,
            label: '已读回执',
            value: _appSettings.readReceiptsEnabled ? '允许发送' : '不发送',
          ),
          const SizedBox(height: PMSpacing.m),
          const _DesktopStatusRow(
            icon: Icons.verified_user_outlined,
            label: '隐私控制',
            value: '已连接后端设置',
          ),
          const Spacer(),
          PMButton(
            label: '修改个人资料',
            icon: Icons.edit_outlined,
            onPressed: _openProfileEditor,
            variant: PMButtonVariant.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildMobilePolicyCard() {
    return PMCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: PMSpacing.l,
            vertical: PMSpacing.s,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            PMSpacing.l,
            0,
            PMSpacing.l,
            PMSpacing.l,
          ),
          title: const Text(
            '当前策略',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: const Text('桌面右侧策略卡在移动端折叠到这里'),
          children: [
            _DesktopStatusRow(
              icon: Icons.lock_outline,
              label: '端到端加密',
              value: _e2eeEnabled ? '已启用' : '未启用',
            ),
            const SizedBox(height: PMSpacing.m),
            _DesktopStatusRow(
              icon: Icons.notifications_outlined,
              label: '消息通知',
              value: _notificationsEnabled ? '已开启' : '已关闭',
            ),
            const SizedBox(height: PMSpacing.m),
            _DesktopStatusRow(
              icon: Icons.done_all,
              label: '已读回执',
              value: _appSettings.readReceiptsEnabled ? '允许发送' : '不发送',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final navigator = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _authService.logout();
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);
    }
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
    WebPushService? webPushService,
  })  : _profileService = profileService,
        _webPushService = webPushService;

  final UserAppSettings initialSettings;
  final UserProfileService? _profileService;
  final WebPushService? _webPushService;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final UserProfileService _profileService;
  late final WebPushService _webPushService;
  late UserAppSettings _settings;
  bool _isSaving = false;
  bool _isWebPushBusy = false;
  WebPushStatus? _webPushStatus;

  @override
  void initState() {
    super.initState();
    _profileService = widget._profileService ?? UserProfileService();
    _webPushService = widget._webPushService ?? WebPushService();
    _settings = widget.initialSettings;
    _loadWebPushStatus();
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

  Future<void> _loadWebPushStatus() async {
    try {
      final status = await _webPushService.getStatus();
      if (!mounted) return;
      setState(() => _webPushStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _webPushStatus = WebPushStatus(
          supported: false,
          standalone: false,
          permission: 'error',
          configured: false,
          message: '后台推送状态读取失败: $error',
        );
      });
    }
  }

  Future<void> _toggleWebPush(bool enabled) async {
    setState(() => _isWebPushBusy = true);
    try {
      final result = enabled
          ? await _webPushService.enable()
          : await _webPushService.disable();
      if (!mounted) return;
      setState(() {
        _webPushStatus = result.status;
        _isWebPushBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? null : Colors.orange,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isWebPushBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('后台推送操作失败: $error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: ListView(
        children: [
          _buildWebPushTile(),
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

  Widget _buildWebPushTile() {
    final status = _webPushStatus;
    final enabled = status?.enabled ?? false;
    final canTap = status?.canRequest == true && !_isWebPushBusy;
    final subtitle = status?.message ?? '正在检查当前浏览器是否支持 PWA 后台推送...';
    return SwitchListTile(
      title: const Text('PWA 后台推送'),
      subtitle: Text(subtitle),
      value: enabled,
      onChanged: canTap ? _toggleWebPush : null,
      secondary: _isWebPushBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.install_mobile_outlined),
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
