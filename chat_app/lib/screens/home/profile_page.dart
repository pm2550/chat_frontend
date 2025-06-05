import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: 实现设置功能
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 用户信息卡片
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [AppColors.cardShadow],
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    child: Icon(Icons.person, size: 30),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                          '用户名',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                    ),
                  ),
                        SizedBox(height: 4),
                  Text(
                    'user@example.com',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      // TODO: 实现编辑个人信息功能
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 功能列表
            _buildMenuItem(
              icon: Icons.chat_bubble_outline,
              title: '聊天设置',
              onTap: () {
                // TODO: 实现聊天设置功能
                    },
                  ),
            _buildMenuItem(
              icon: Icons.notifications,
              title: '通知设置',
              onTap: () {
                // TODO: 实现通知设置功能
                    },
                  ),
                  _buildMenuItem(
              icon: Icons.privacy_tip,
              title: '隐私设置',
                    onTap: () {
                // TODO: 实现隐私设置功能
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.help_outline,
                    title: '帮助与反馈',
                    onTap: () {
                // TODO: 实现帮助功能
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.info_outline,
              title: '关于',
                    onTap: () {
                // TODO: 实现关于页面
                    },
            ),

            const SizedBox(height: 24),

            // 退出登录按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _showLogoutDialog();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('退出登录'),
              ),
            ),
          ],
        ),
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

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('您确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
} 