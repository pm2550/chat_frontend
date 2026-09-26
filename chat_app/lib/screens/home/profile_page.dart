import 'package:flutter/material.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../settings/chat_preferences_screen.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/pm_responsive.dart';
import '../profile/about_app_dialog.dart';
import 'add_friend_screen.dart';
import '../profile/profile_edit_screen.dart';
import '../profile/starred_messages_screen.dart';
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

class _ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin<ProfilePage> {
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

  void _showMyFriendCode() {
    final user = _currentUser;
    if (user == null) return;
    showMyFriendCode(context, user);
  }

  void _openStarredMessages() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StarredMessagesScreen()),
    );
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
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
        body: PMDesktopPage(
            maxWidth: 1040,
            child: Column(children: [
              PMPageHeader(title: '我的', subtitle: '让聊天更像你，也照顾好自己的节奏', actions: [
                IconButton(
                    tooltip: '刷新',
                    onPressed: () => _loadProfile(),
                    icon: const Icon(Icons.refresh)),
                PMButton(
                    label: '设置',
                    icon: Icons.settings_outlined,
                    variant: PMButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()))),
              ]),
              const SizedBox(height: PMSpacing.xl),
              Expanded(
                  child: RefreshIndicator(
                      onRefresh: () => _loadProfile(showLoading: false),
                      child: _buildBody())),
            ])));
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null && _currentUser == null) {
      return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: 420, child: _buildErrorState())]);
    }
    final user = _currentUser;
    if (user == null) return const Center(child: Text('未找到用户信息'));
    return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(PMSpacing.l),
        children: [
          _buildProfileHeader(user),
          const SizedBox(height: PMSpacing.l),
          if (_errorMessage != null) _buildInlineWarning(_errorMessage!),
          Row(children: [
            Expanded(
                child: _buildQuickEntry(
                    Icons.star_border_rounded, '我的收藏', _openStarredMessages)),
            const SizedBox(width: PMSpacing.s),
            Expanded(
                child: _buildQuickEntry(
                    Icons.palette_outlined,
                    '聊天装扮',
                    () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatPreferencesScreen(
                            profileService: _profileService))))),
            const SizedBox(width: PMSpacing.s),
            Expanded(
                child: _buildQuickEntry(
                    Icons.qr_code_2, '我的二维码', _showMyFriendCode)),
          ]),
          const SizedBox(height: PMSpacing.xl),
          PMSectionCard(title: '偏好与设置', children: [
            _buildMenuItem(
                icon: Icons.notifications_none_rounded,
                title: '通知设置',
                onTap: _openNotificationSettings),
            _buildMenuItem(
                icon: Icons.shield_outlined,
                title: '隐私设置',
                onTap: _openPrivacySettings),
            _buildMenuItem(
                icon: Icons.tune_rounded,
                title: '更多设置',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ]),
          const SizedBox(height: PMSpacing.l),
          PMCard(
              elevated: false,
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.badge_outlined),
                title: const Text('账号资料'),
                subtitle: const Text('联系信息与账户详情',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                children: [_buildContactInfo(user), _buildAccountInfo(user)],
              )),
          const SizedBox(height: PMSpacing.l),
          _buildMenuItem(
              icon: Icons.info_outline,
              title: '关于',
              onTap: () => showAboutAppDialog(context)),
          const SizedBox(height: PMSpacing.l),
          Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('退出登录'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary))),
        ]);
  }

  Widget _buildQuickEntry(IconData icon, String title, VoidCallback onTap) =>
      PMCard(
        padding: const EdgeInsets.symmetric(
            vertical: PMSpacing.l, horizontal: PMSpacing.xs),
        onTap: onTap,
        child: Column(children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: PMSpacing.s),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _buildProfileHeader(User user) {
    return PMCard(
        radius: PMRadius.l,
        padding: const EdgeInsets.all(PMSpacing.xl),
        child: Column(children: [
          Row(children: [
            CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.pixelBlue,
                backgroundImage: _avatarProvider(user),
                child: _avatarProvider(user) == null
                    ? Text(_avatarText(user),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 24,
                            fontWeight: FontWeight.w700))
                    : null),
            const SizedBox(width: PMSpacing.l),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_displayName(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w700)),
                  const SizedBox(height: PMSpacing.xs),
                  Text('@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  if (user.bio?.isNotEmpty == true)
                    Text(user.bio!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                ])),
            IconButton(
                tooltip: '编辑资料',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: _editProfile),
          ]),
          const SizedBox(height: PMSpacing.l),
          const Divider(),
          const SizedBox(height: PMSpacing.m),
          _buildOnlineStatus(user),
        ]));
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
    return Wrap(
        spacing: PMSpacing.xs,
        runSpacing: PMSpacing.xs,
        children: OnlineStatus.values
            .map((status) => ChoiceChip(
                  selected: status == user.onlineStatus,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: PMSpacing.xs),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    _buildStatusDot(status),
                    const SizedBox(width: PMSpacing.xs),
                    Text(status.description,
                        style: const TextStyle(fontSize: 12))
                  ]),
                  onSelected: (_) => _updateOnlineStatus(status),
                ))
            .toList());
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

  Widget _buildSection({required String title, required Widget child}) =>
      PMSectionCard(title: title, children: [child]);

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

  Widget _buildMenuItem(
      {required IconData icon,
      required String title,
      required VoidCallback onTap}) {
    return PMListRow(
        leading: Icon(icon, color: AppColors.primary, size: 22),
        title: Text(title),
        onTap: onTap);
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
