import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/auth_service.dart';
import '../../widgets/pm_brand.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  int get _passwordScore {
    final password = _passwordController.text;
    var score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return score.clamp(0, 5);
  }

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_handlePasswordChanged);
  }

  void _handlePasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_handlePasswordChanged);
    _usernameController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final result = await _authService.register(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      displayName: _displayNameController.text.trim().isEmpty
          ? _usernameController.text.trim()
          : _displayNameController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    final success = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(result['message']?.toString() ?? (success ? '注册成功' : '注册失败')),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );

    if (success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 920;

    return Scaffold(
      body: PMChatPattern(
        dense: !isWide,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? PMSpacing.xxxl : PMSpacing.l,
                vertical: isWide ? PMSpacing.xxl : PMSpacing.l,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(),
                    const SizedBox(height: PMSpacing.xxl),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildHeroPanel()),
                          const SizedBox(width: PMSpacing.xxl),
                          SizedBox(width: 480, child: _buildFormCard()),
                        ],
                      )
                    else
                      Column(
                        children: [
                          _buildCompactHeader(),
                          const SizedBox(height: PMSpacing.l),
                          _buildFormCard(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        const Expanded(child: PMChatLogo(size: 44)),
        PMButton(
          label: '返回登录',
          icon: Icons.arrow_back,
          compact: true,
          variant: PMButtonVariant.secondary,
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildCompactHeader() {
    return const Column(
      children: [
        PMChatMark(size: 72),
        SizedBox(height: PMSpacing.l),
        Text(
          '创建 PM chat 账号',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: PMSpacing.s),
        Text(
          '注册后返回登录页使用新账号登录。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroPanel() {
    return PMCard(
      radius: PMRadius.xl,
      padding: const EdgeInsets.all(PMSpacing.xxl),
      background: Colors.white.withValues(alpha: 0.96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(PMRadius.l),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: PMSpacing.xxl),
          const Text(
            '加入你的团队消息工作台',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: PMSpacing.l),
          const Text(
            '账号创建后可以进入聊天、资料库、Bot 协作和实时工作区。这里先完成基础身份信息，后续资料可在个人中心继续编辑。',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
          const SizedBox(height: PMSpacing.xxl),
          const _TrustTile(
            icon: Icons.lock_outline,
            title: '密码本地强度提示',
            subtitle: '只做输入质量提示，不改变后端注册协议。',
          ),
          const SizedBox(height: PMSpacing.m),
          const _TrustTile(
            icon: Icons.groups_2_outlined,
            title: '面向团队协作',
            subtitle: '同一账号可用于消息、联系人和资料库权限。',
          ),
          const SizedBox(height: PMSpacing.m),
          const _TrustTile(
            icon: Icons.smart_toy_outlined,
            title: 'Bot 和 Agent 就绪',
            subtitle: '后续能力通过同一身份和权限体系衔接。',
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return PMCard(
      radius: PMRadius.l,
      padding: const EdgeInsets.all(PMSpacing.xl),
      background: Colors.white.withValues(alpha: 0.98),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '创建账号',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: PMSpacing.xs),
            const Text(
              '请填写登录信息。昵称可选，留空时使用用户名。',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: PMSpacing.xl),
            TextFormField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                label: '用户名',
                hint: '至少 3 个字符',
                icon: Icons.person_outline,
                required: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入用户名';
                }
                if (value.trim().length < 3) {
                  return '用户名至少 3 个字符';
                }
                return null;
              },
            ),
            const SizedBox(height: PMSpacing.l),
            TextFormField(
              controller: _displayNameController,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                label: '昵称',
                hint: '可选',
                icon: Icons.badge_outlined,
              ),
            ),
            const SizedBox(height: PMSpacing.l),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                label: '邮箱',
                hint: 'name@example.com',
                icon: Icons.mail_outline,
                required: true,
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return '请输入邮箱';
                if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$')
                    .hasMatch(email)) {
                  return '请输入有效邮箱';
                }
                return null;
              },
            ),
            const SizedBox(height: PMSpacing.l),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                label: '密码',
                hint: '至少 6 个字符',
                icon: Icons.lock_outline,
                required: true,
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入密码';
                if (value.length < 6) return '密码至少 6 个字符';
                return null;
              },
            ),
            const SizedBox(height: PMSpacing.s),
            _PasswordStrength(score: _passwordScore),
            const SizedBox(height: PMSpacing.l),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _isLoading ? null : _register(),
              decoration: _inputDecoration(
                label: '确认密码',
                icon: Icons.lock_reset,
                required: true,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return '请再次输入密码';
                if (value != _passwordController.text) {
                  return '两次输入的密码不一致';
                }
                return null;
              },
            ),
            const SizedBox(height: PMSpacing.xl),
            PMButton(
              label: '创建账号',
              icon: Icons.person_add_alt_1,
              loading: _isLoading,
              onPressed: _isLoading ? null : _register,
            ),
            const SizedBox(height: PMSpacing.m),
            PMButton(
              label: '已有账号？返回登录',
              variant: PMButtonVariant.link,
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
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
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = switch (score) {
      0 || 1 => AppColors.error,
      2 || 3 => AppColors.warning,
      _ => AppColors.success,
    };
    final label = switch (score) {
      0 => '等待输入',
      1 => '较弱',
      2 || 3 => '可用',
      _ => '较强',
    };

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PMRadius.pill),
            child: LinearProgressIndicator(
              value: score == 0 ? 0.08 : score / 5,
              minHeight: 6,
              backgroundColor: AppColors.borderLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: PMSpacing.m),
        SizedBox(
          width: 58,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrustTile extends StatelessWidget {
  const _TrustTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PMSpacing.l),
      decoration: BoxDecoration(
        color: AppColors.cloud.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(PMRadius.m),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.pixelBlue,
              borderRadius: BorderRadius.circular(PMRadius.m),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: PMSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: PMSpacing.xs),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
