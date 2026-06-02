import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/bot_service.dart';
import '../../widgets/pm_brand.dart';

/// Standalone "My API Keys" management screen: bring-your-own provider keys with
/// an optional OpenAI-compatible endpoint (base_url) and default model. This is
/// the only UI path that creates credentials carrying a base_url — bots then pick
/// a saved credential from the vault.
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key, this.botService});

  final BotService? botService;

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  static const List<String> _providers = [
    'OPENAI',
    'CLAUDE',
    'DEEPSEEK',
    'OLLAMA',
    'HERMES',
    'DASHSCOPE',
  ];

  late final BotService _botService;
  bool _loading = true;
  String? _error;
  List<ProviderCredential> _credentials = const [];

  bool _showForm = false;
  bool _saving = false;
  String _provider = 'OPENAI';
  final _labelController = TextEditingController();
  final _secretController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _botService = widget.botService ?? BotService();
    _load();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _secretController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _botService.getProviderCredentials();
      if (!mounted) return;
      setState(() {
        _credentials = list;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    if (_labelController.text.trim().isEmpty ||
        _secretController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写名称和密钥')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _botService.createProviderCredential(
        provider: _provider,
        label: _labelController.text.trim(),
        secret: _secretController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        modelOverride: _modelController.text.trim(),
      );
      if (!mounted) return;
      _labelController.clear();
      _secretController.clear();
      _baseUrlController.clear();
      _modelController.clear();
      setState(() {
        _saving = false;
        _showForm = false;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密钥已保存')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $error')),
      );
    }
  }

  Future<void> _delete(ProviderCredential credential) async {
    try {
      await _botService.deleteProviderCredential(credential.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.all(PMSpacing.xl),
                children: [
                  PMPageHeader(
                    title: '我的 API 密钥',
                    subtitle: '自带模型密钥与接入点（base_url），机器人可从保险箱选用',
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(PMRadius.s),
                      ),
                      child: const Icon(Icons.vpn_key, color: Colors.white),
                    ),
                    actions: [
                      PMButton(
                        label: '返回',
                        icon: Icons.arrow_back,
                        compact: true,
                        variant: PMButtonVariant.secondary,
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: PMSpacing.xl),
                  PMButton(
                    label: _showForm ? '取消添加' : '添加密钥',
                    icon: _showForm ? Icons.close : Icons.add,
                    onPressed: () => setState(() => _showForm = !_showForm),
                  ),
                  if (_showForm) ...[
                    const SizedBox(height: PMSpacing.l),
                    _buildForm(),
                  ],
                  const SizedBox(height: PMSpacing.xl),
                  _buildBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(PMSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return PMEmptyState(
        icon: Icons.error_outline,
        title: '加载失败',
        subtitle: _error,
        variant: EmptyStateVariant.muted,
        action: PMButton(
          label: '重试',
          icon: Icons.refresh,
          onPressed: _load,
        ),
      );
    }
    if (_credentials.isEmpty) {
      return const PMEmptyState(
        icon: Icons.vpn_key_off,
        title: '还没有密钥',
        subtitle: '点击“添加密钥”接入你自己的模型服务（文字或画图）',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _credentials.map(_buildRow).toList(),
    );
  }

  Widget _buildForm() {
    return PMCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '提供者',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: PMSpacing.s),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: _providers
                .map(
                  (p) => PMChip(
                    label: p,
                    selected: _provider == p,
                    onTap: () => setState(() => _provider = p),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: PMSpacing.m),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '名称',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: PMSpacing.s),
          TextField(
            controller: _secretController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              prefixIcon: Icon(Icons.key),
            ),
          ),
          const SizedBox(height: PMSpacing.s),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL（可选，OpenAI 兼容接入点）',
              hintText: 'https://… 或 http://localhost/…',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: PMSpacing.s),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: '默认模型（可选）',
              prefixIcon: Icon(Icons.tune),
            ),
          ),
          const SizedBox(height: PMSpacing.l),
          PMButton(
            label: '保存密钥',
            icon: Icons.save,
            loading: _saving,
            onPressed: _saving ? null : _create,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ProviderCredential credential) {
    final parts = <String>[credential.llmProvider];
    if (credential.secretLast4 != null && credential.secretLast4!.isNotEmpty) {
      parts.add('····${credential.secretLast4}');
    }
    if (credential.baseUrl != null && credential.baseUrl!.isNotEmpty) {
      parts.add(credential.baseUrl!);
    }
    if (credential.modelOverride != null &&
        credential.modelOverride!.isNotEmpty) {
      parts.add(credential.modelOverride!);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: PMSpacing.s),
      child: PMListRow(
        leading: const Icon(Icons.vpn_key, color: AppColors.secondary),
        title: Text(credential.label),
        subtitle: Text(parts.join(' · ')),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: () => _delete(credential),
        ),
      ),
    );
  }
}
