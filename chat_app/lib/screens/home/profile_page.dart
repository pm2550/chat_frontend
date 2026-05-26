import 'package:flutter/material.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_brand.dart';
import '../../constants/app_colors.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../profile/profile_edit_screen.dart';
import '../settings/settings_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.profileService,
    this.authService,
    this.avatarPicker,
  });

  final UserProfileService? profileService;
  final AuthService? authService;
  final ProfileAvatarPicker? avatarPicker;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final UserProfileService _profileService;
  late final AuthService _authService;

  User? _currentUser;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _profileService = widget.profileService ?? UserProfileService();
    _currentUser = _authService.currentUser;
    _loadProfile(showLoading: _currentUser == null);
  }

  Future<void> _loadProfile({bool showLoading = true}) async {
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final user = await _profileService.getProfile();
      if (!mounted) return;
      setState(() {
        _currentUser = user;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _editProfile() async {
    final user = _currentUser;
    if (user == null) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          user: user,
          profileService: _profileService,
          avatarPicker: widget.avatarPicker,
        ),
      ),
    );
    if (changed == true) {
      await _loadProfile(showLoading: false);
    }
  }

  Future<void> _updateOnlineStatus(OnlineStatus status) async {
    final user = _currentUser;
    if (user == null || status == user.onlineStatus) return;

    try {
      final updatedStatus = await _profileService.updateOnlineStatus(status);
      if (!mounted) return;
      setState(() {
        _currentUser = user.copyWith(onlineStatus: updatedStatus);
      });
      _showSnackBar('状态已更新为 ${updatedStatus.description}');
    } catch (e) {
      _showSnackBar('状态更新失败: $e', isError: true);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('您确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.logout();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      final settings = await _profileService.getSettings();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotificationSettingsScreen(
            initialSettings: settings,
            profileService: _profileService,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('设置加载失败: $e', isError: true);
    }
  }

  Future<void> _openPrivacySettings() async {
    try {
      final settings = await _profileService.getSettings();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PrivacySettingsScreen(
            initialSettings: settings,
            profileService: _profileService,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('设置加载失败: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktopScaffold();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadProfile(),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadProfile(showLoading: false),
        child: _buildBody(),
      ),
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
                  title: '个人中心',
                  subtitle: '管理账号资料、在线状态、通知和隐私偏好',
                  icon: Icons.account_circle,
                  actions: [
                    OutlinedButton.icon(
                      onPressed: () => _loadProfile(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
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
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('设置'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: _buildDesktopBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _currentUser == null) {
      return PMDesktopCard(child: _buildErrorState());
    }

    final user = _currentUser;
    if (user == null) {
      return const Center(child: Text('未找到用户信息'));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            children: [
              _buildProfileHeader(user),
              const SizedBox(height: 16),
              if (_errorMessage != null) _buildInlineWarning(_errorMessage!),
              _buildOnlineStatus(user),
              const SizedBox(height: 16),
              _buildContactInfo(user),
              const SizedBox(height: 16),
              _buildAccountInfo(user),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 360,
          child: ListView(
            children: [
              PMDesktopCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PMSectionHeader(
                      title: '账号操作',
                      subtitle: '通知、隐私和账号信息',
                    ),
                    const SizedBox(height: 14),
                    _buildMenuItem(
                      icon: Icons.notifications,
                      title: '通知设置',
                      onTap: _openNotificationSettings,
                    ),
                    _buildMenuItem(
                      icon: Icons.privacy_tip,
                      title: '隐私设置',
                      onTap: _openPrivacySettings,
                    ),
                    _buildMenuItem(
                      icon: Icons.info_outline,
                      title: '关于',
                      onTap: () => _showSnackBar(AppBrand.name),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PMDesktopCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PMSectionHeader(
                      title: '会话身份',
                      subtitle: '当前账号会用于聊天、文件和工作区任务',
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _editProfile,
                      icon: const Icon(Icons.edit),
                      label: const Text('编辑资料'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('退出登录'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
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
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _currentUser == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: _buildErrorState(),
          ),
        ],
      );
    }

    final user = _currentUser;
    if (user == null) {
      return const Center(child: Text('未找到用户信息'));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildProfileHeader(user),
        const SizedBox(height: 16),
        if (_errorMessage != null) _buildInlineWarning(_errorMessage!),
        _buildOnlineStatus(user),
        const SizedBox(height: 16),
        _buildContactInfo(user),
        const SizedBox(height: 16),
        _buildAccountInfo(user),
        const SizedBox(height: 16),
        _buildMenuItem(
          icon: Icons.notifications,
          title: '通知设置',
          onTap: _openNotificationSettings,
        ),
        _buildMenuItem(
          icon: Icons.privacy_tip,
          title: '隐私设置',
          onTap: _openPrivacySettings,
        ),
        _buildMenuItem(
          icon: Icons.info_outline,
          title: '关于',
          onTap: () => _showSnackBar(AppBrand.name),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileHeader(User user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            backgroundImage: _avatarProvider(user),
            child: _avatarProvider(user) == null
                ? Text(
                    _avatarText(user),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName(user),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: const TextStyle(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.bio != null && user.bio!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    user.bio!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '编辑资料',
            icon: const Icon(Icons.edit),
            onPressed: _editProfile,
          ),
        ],
      ),
    );
  }

  Widget _buildInlineWarning(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineStatus(User user) {
    return _buildSection(
      title: '在线状态',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: OnlineStatus.values.map((status) {
          final selected = status == user.onlineStatus;
          return ChoiceChip(
            selected: selected,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusDot(status),
                const SizedBox(width: 6),
                Text(status.description),
              ],
            ),
            onSelected: (_) => _updateOnlineStatus(status),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContactInfo(User user) {
    return _buildSection(
      title: '联系信息',
      child: Column(
        children: [
          _buildInfoRow(Icons.email, '邮箱', user.email),
          if (user.phone != null && user.phone!.isNotEmpty)
            _buildInfoRow(Icons.phone, '手机号', user.phone!),
          if (user.bio != null && user.bio!.isNotEmpty)
            _buildInfoRow(Icons.notes, '简介', user.bio!),
        ],
      ),
    );
  }

  Widget _buildAccountInfo(User user) {
    return _buildSection(
      title: '账户信息',
      child: Column(
        children: [
          _buildInfoRow(Icons.person, '用户名', user.username),
          _buildInfoRow(Icons.circle, '状态', user.onlineStatus.description),
          _buildInfoRow(
              Icons.calendar_today, '注册时间', _formatDateTime(user.createdAt)),
          if (user.lastSeen != null)
            _buildInfoRow(
              Icons.access_time,
              '最后在线',
              _formatDateTime(user.lastSeen!),
            ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              '资料加载失败',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProfile,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot(OnlineStatus status) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: _statusColor(status),
        shape: BoxShape.circle,
      ),
    );
  }

  ImageProvider? _avatarProvider(User user) {
    final avatarUrl = user.avatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) return null;
    return NetworkImage(ApiConstants.resolveFileUrl(avatarUrl));
  }

  String _avatarText(User user) {
    final name = _displayName(user);
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _displayName(User user) {
    if (user.displayName.isNotEmpty) return user.displayName;
    if (user.username.isNotEmpty) return user.username;
    return user.email;
  }

  Color _statusColor(OnlineStatus status) {
    switch (status) {
      case OnlineStatus.online:
        return AppColors.online;
      case OnlineStatus.away:
        return AppColors.warning;
      case OnlineStatus.busy:
        return AppColors.error;
      case OnlineStatus.offline:
        return AppColors.textSecondary;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }
}
