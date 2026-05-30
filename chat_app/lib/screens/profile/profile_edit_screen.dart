import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/user.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/pm_brand.dart';

typedef ProfileAvatarPicker = Future<PickedProfileAvatar?> Function();

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.user,
    this.profileService,
    this.avatarPicker,
  });

  final User user;
  final UserProfileService? profileService;
  final ProfileAvatarPicker? avatarPicker;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final UserProfileService _profileService;
  late final TextEditingController _displayNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _bioController;

  OnlineStatus _selectedStatus = OnlineStatus.online;
  PickedProfileAvatar? _selectedAvatar;
  List<int>? _avatarPreviewBytes;
  String? _avatarUrl;
  bool _isLoading = false;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? UserProfileService();
    _displayNameController =
        TextEditingController(text: widget.user.displayName);
    _emailController = TextEditingController(text: widget.user.email);
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
    _bioController = TextEditingController(text: widget.user.bio ?? '');
    _selectedStatus = widget.user.onlineStatus;
    _avatarUrl = widget.user.avatarUrl;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<PickedProfileAvatar?> _pickAvatarFromGallery() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null) return null;
    return PickedProfileAvatar(
      name: image.name,
      path: kIsWeb ? null : image.path,
      size: await image.length(),
      mimeType: image.mimeType,
      bytes: await image.readAsBytes(),
    );
  }

  Future<void> _selectAvatar() async {
    try {
      final picker = widget.avatarPicker ?? _pickAvatarFromGallery;
      final avatar = await picker();
      if (avatar == null || !mounted) return;
      setState(() {
        _selectedAvatar = avatar;
        _avatarPreviewBytes = avatar.bytes;
      });
    } catch (e) {
      _showErrorSnackBar('选择图片失败: $e');
    }
  }

  Future<void> _uploadAvatar() async {
    final avatar = _selectedAvatar;
    if (avatar == null) return;

    setState(() {
      _isUploadingAvatar = true;
    });

    try {
      final avatarUrl = await _profileService.uploadAvatar(avatar);
      if (!mounted) return;
      setState(() {
        _avatarUrl = avatarUrl;
        _selectedAvatar = null;
        _avatarPreviewBytes = avatar.bytes;
      });
      _showSuccessSnackBar('头像上传成功');
    } catch (e) {
      _showErrorSnackBar('头像上传失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() {
      _isUploadingAvatar = true;
    });

    try {
      await _profileService.deleteAvatar();
      if (!mounted) return;
      setState(() {
        _avatarUrl = null;
        _selectedAvatar = null;
        _avatarPreviewBytes = null;
      });
      _showSuccessSnackBar('头像删除成功');
    } catch (e) {
      _showErrorSnackBar('头像删除失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final request = UserProfileUpdateRequest(
        displayName: _displayNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        onlineStatus: _selectedStatus.name.toUpperCase(),
      );

      await _profileService.updateProfile(request);
      if (!mounted) return;
      _showSuccessSnackBar('资料更新成功');
      Navigator.of(context).pop(true);
    } catch (e) {
      _showErrorSnackBar('资料更新失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 980;

    return Scaffold(
      body: PMChatPattern(
        dense: !isWide,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isWide ? PMSpacing.xxl : PMSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PMPageHeader(
                  title: '编辑资料',
                  subtitle: '更新头像、身份信息和在线状态',
                  leading: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(PMRadius.l),
                    ),
                    child: const Icon(
                      Icons.manage_accounts_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  actions: [
                    PMButton(
                      label: '返回',
                      icon: Icons.arrow_back,
                      compact: true,
                      variant: PMButtonVariant.secondary,
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                    ),
                    Tooltip(
                      message: '保存',
                      child: IconButton.filled(
                        onPressed: _isLoading ? null : _updateProfile,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PMSpacing.xl),
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 340,
                                  child: Column(
                                    children: [
                                      _buildAvatarSection(),
                                      const SizedBox(height: PMSpacing.l),
                                      _buildStatusSummary(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: PMSpacing.xl),
                                Expanded(
                                  child: Column(
                                    children: [
                                      _buildBasicInfoSection(),
                                      const SizedBox(height: PMSpacing.l),
                                      _buildOnlineStatusSection(),
                                      const SizedBox(height: PMSpacing.xl),
                                      _buildSaveBar(),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _buildAvatarSection(),
                                const SizedBox(height: PMSpacing.l),
                                _buildBasicInfoSection(),
                                const SizedBox(height: PMSpacing.l),
                                _buildOnlineStatusSection(),
                                const SizedBox(height: PMSpacing.xl),
                                _buildSaveBar(),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return PMCard(
      radius: PMRadius.l,
      padding: const EdgeInsets.all(PMSpacing.xl),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  gradient: _avatarImageProvider() == null
                      ? AppColors.primaryGradient
                      : null,
                  borderRadius: BorderRadius.circular(PMRadius.xl),
                  boxShadow: const [PMElevation.card],
                  image: _avatarImageProvider() == null
                      ? null
                      : DecorationImage(
                          image: _avatarImageProvider()!,
                          fit: BoxFit.cover,
                        ),
                ),
                child: _avatarImageProvider() == null
                    ? Text(
                        _avatarFallback,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          height: 2.55,
                        ),
                      )
                    : null,
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _statusColor(_selectedStatus),
                  borderRadius: BorderRadius.circular(PMRadius.pill),
                  border: Border.all(color: Colors.white, width: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.l),
          Text(
            _displayNameController.text.trim().isEmpty
                ? widget.user.displayName
                : _displayNameController.text.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: PMSpacing.xs),
          Text(
            widget.user.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: PMSpacing.l),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            alignment: WrapAlignment.center,
            children: [
              PMButton(
                label: '选择头像',
                icon: Icons.photo_library_outlined,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: _isUploadingAvatar ? null : _selectAvatar,
              ),
              if (_selectedAvatar != null)
                PMButton(
                  label: '上传',
                  icon: Icons.upload_outlined,
                  compact: true,
                  loading: _isUploadingAvatar,
                  onPressed: _isUploadingAvatar ? null : _uploadAvatar,
                ),
              if (_avatarUrl != null)
                PMButton(
                  label: '删除',
                  icon: Icons.delete_outline,
                  compact: true,
                  variant: PMButtonVariant.danger,
                  onPressed: _isUploadingAvatar ? null : _deleteAvatar,
                ),
            ],
          ),
          if (_selectedAvatar != null) ...[
            const SizedBox(height: PMSpacing.m),
            PMChip(
              label: '待上传: ${_selectedAvatar!.name}',
              icon: Icons.upload_file_outlined,
              selected: true,
              color: AppColors.warning,
            ),
          ],
          if (_isUploadingAvatar) ...[
            const SizedBox(height: PMSpacing.m),
            const PMProgressStrip(label: '正在处理头像...'),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusSummary() {
    return PMSectionCard(
      title: '资料状态',
      subtitle: '保存后会同步到联系人、消息头像和成员列表',
      children: [
        PMListRow(
          leading: const _IconTile(
            icon: Icons.alternate_email_outlined,
            color: AppColors.primary,
          ),
          title: const Text('用户名'),
          subtitle: Text(widget.user.username),
        ),
        PMListRow(
          leading: _IconTile(
            icon: Icons.circle,
            color: _statusColor(_selectedStatus),
          ),
          title: const Text('当前状态'),
          subtitle: Text(_selectedStatus.description),
        ),
      ],
    );
  }

  ImageProvider? _avatarImageProvider() {
    final previewBytes = _avatarPreviewBytes ?? _selectedAvatar?.bytes;
    if (previewBytes != null) {
      return MemoryImage(Uint8List.fromList(previewBytes));
    }
    final avatarUrl = _avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return NetworkImage(ApiConstants.resolveFileUrl(avatarUrl));
    }
    return null;
  }

  Widget _buildBasicInfoSection() {
    return PMSectionCard(
      title: '基本信息',
      subtitle: '显示名称和邮箱为必填，电话和简介可选',
      padding: const EdgeInsets.all(PMSpacing.xl),
      children: [
        Padding(
          padding: const EdgeInsets.all(PMSpacing.m),
          child: Column(
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: _inputDecoration(
                  label: '显示名称',
                  icon: Icons.person_outline,
                  required: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入显示名称';
                  }
                  if (value.trim().length > 100) {
                    return '显示名称不能超过100字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: PMSpacing.l),
              TextFormField(
                controller: _emailController,
                decoration: _inputDecoration(
                  label: '邮箱',
                  icon: Icons.email_outlined,
                  required: true,
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入邮箱地址';
                  }
                  if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$')
                      .hasMatch(value.trim())) {
                    return '请输入有效的邮箱地址';
                  }
                  return null;
                },
              ),
              const SizedBox(height: PMSpacing.l),
              TextFormField(
                controller: _phoneController,
                decoration: _inputDecoration(
                  label: '手机号',
                  hint: '可选',
                  icon: Icons.phone_outlined,
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: PMSpacing.l),
              TextFormField(
                controller: _bioController,
                decoration: _inputDecoration(
                  label: '个人简介',
                  hint: '可选，最多 500 字',
                  icon: Icons.notes_outlined,
                ),
                maxLines: 4,
                maxLength: 500,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineStatusSection() {
    return PMSectionCard(
      title: '在线状态',
      subtitle: '影响联系人列表、群成员栏和消息发送侧的状态展示',
      padding: const EdgeInsets.all(PMSpacing.xl),
      children: [
        Padding(
          padding: const EdgeInsets.all(PMSpacing.m),
          child: Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: OnlineStatus.values
                .map(
                  (status) => PMChip(
                    label: status.description,
                    icon: Icons.circle,
                    selected: _selectedStatus == status,
                    color: _statusColor(status),
                    onTap: () => setState(() => _selectedStatus = status),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveBar() {
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.l),
      elevated: false,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '保存后会返回上一页，并刷新个人资料缓存。',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: PMSpacing.l),
          PMButton(
            label: '保存更改',
            icon: Icons.save_outlined,
            loading: _isLoading,
            onPressed: _isLoading ? null : _updateProfile,
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: required ? '必填' : null,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.cloud.withValues(alpha: 0.55),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PMRadius.s),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PMRadius.s),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PMRadius.s),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  String get _avatarFallback {
    final text = _displayNameController.text.trim().isNotEmpty
        ? _displayNameController.text.trim()
        : widget.user.displayName;
    if (text.isEmpty) return '?';
    return String.fromCharCode(text.runes.first).toUpperCase();
  }

  static Color _statusColor(OnlineStatus status) {
    return switch (status) {
      OnlineStatus.online => AppColors.online,
      OnlineStatus.away => AppColors.away,
      OnlineStatus.busy => AppColors.busy,
      OnlineStatus.offline => AppColors.offline,
    };
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(PMRadius.m),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
