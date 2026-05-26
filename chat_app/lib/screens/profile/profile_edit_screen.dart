import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/api_constants.dart';
import '../../models/user.dart';
import '../../services/user_profile_service.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: _isLoading ? null : _updateProfile,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildAvatarSection(),
              const SizedBox(height: 24),
              _buildBasicInfoSection(),
              const SizedBox(height: 24),
              _buildOnlineStatusSection(),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _updateProfile,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('保存更改'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: _avatarImageProvider(),
              child: _avatarImageProvider() == null
                  ? const Icon(Icons.person, size: 50)
                  : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isUploadingAvatar ? null : _selectAvatar,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('选择头像'),
                ),
                if (_selectedAvatar != null)
                  ElevatedButton.icon(
                    onPressed: _isUploadingAvatar ? null : _uploadAvatar,
                    icon: _isUploadingAvatar
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload),
                    label: const Text('上传'),
                  ),
                if (_avatarUrl != null)
                  OutlinedButton.icon(
                    onPressed: _isUploadingAvatar ? null : _deleteAvatar,
                    icon: const Icon(Icons.delete),
                    label: const Text('删除'),
                  ),
              ],
            ),
          ],
        ),
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '基本信息',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: '显示名称',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: '邮箱',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: '手机号（可选）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: '个人简介（可选）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineStatusSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在线状态',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...OnlineStatus.values.map(
              (status) => RadioListTile<OnlineStatus>(
                title: Text(status.description),
                value: status,
                // ignore: deprecated_member_use
                groupValue: _selectedStatus,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
