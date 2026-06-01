import 'dart:convert';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/bot_service.dart';
import '../../widgets/pm_brand.dart';

class BotEditScreen extends StatefulWidget {
  const BotEditScreen({
    super.key,
    this.bot,
    this.botService,
  });

  final BotConfig? bot;
  final BotService? botService;

  @override
  State<BotEditScreen> createState() => _BotEditScreenState();
}

class _BotEditScreenState extends State<BotEditScreen> {
  late final BotService _botService;
  late final TextEditingController _nameController;
  late final TextEditingController _providerController;
  late final TextEditingController _modelController;
  late final TextEditingController _promptController;
  late final TextEditingController _apiKeyController;

  final _formKey = GlobalKey<FormState>();
  double _temperature = 0.7;
  int _maxTokens = 2048;
  bool _saving = false;
  bool _loadingCredentials = false;
  bool _characterBusy = false;
  List<ProviderCredential> _credentials = const [];
  int? _selectedCredentialId;
  bool _hasCharacterCard = false;
  String? _characterPersona;
  String? _characterScenario;
  String? _characterFirstMes;
  List<String> _alternateGreetings = const [];
  int _bookEntryCount = 0;

  bool get _isEditing => widget.bot?.id != null;

  @override
  void initState() {
    super.initState();
    _botService = widget.botService ?? BotService();
    final bot = widget.bot;
    _nameController = TextEditingController(text: bot?.botName ?? '');
    _providerController =
        TextEditingController(text: bot?.llmProvider ?? 'OPENAI');
    _modelController = TextEditingController(text: bot?.modelName ?? '');
    _promptController = TextEditingController(text: bot?.systemPrompt ?? '');
    _apiKeyController = TextEditingController();
    _providerController.addListener(_loadCredentialsForProvider);
    _temperature = bot?.temperature ?? 0.7;
    _maxTokens = bot?.maxTokens ?? 2048;
    _selectedCredentialId = bot?.providerCredentialId;
    _hasCharacterCard = bot?.hasCharacterCard ?? false;
    _characterPersona = bot?.characterPersona;
    _characterScenario = bot?.characterScenario;
    _characterFirstMes = bot?.characterFirstMes;
    _alternateGreetings = bot?.characterAlternateGreetings ?? const [];
    _bookEntryCount = bot?.characterBookEntryCount ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCredentialsForProvider();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    _apiKeyController.dispose();
    super.dispose();
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
                    title: _isEditing ? '编辑 Bot' : '新建 Bot',
                    subtitle: '配置模型、系统提示词和运行参数',
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(PMRadius.s),
                      ),
                      child: const Icon(Icons.smart_toy, color: Colors.white),
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
                  PMCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Bot 名称',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? '请输入 Bot 名称'
                                    : null,
                          ),
                          const SizedBox(height: PMSpacing.l),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 620;
                              final provider = TextFormField(
                                controller: _providerController,
                                decoration: const InputDecoration(
                                  labelText: 'LLM Provider',
                                  prefixIcon: Icon(Icons.cloud_queue),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? '请输入 Provider'
                                        : null,
                              );
                              final model = TextFormField(
                                controller: _modelController,
                                decoration: const InputDecoration(
                                  labelText: '模型名',
                                  prefixIcon: Icon(Icons.memory),
                                  hintText: '例如 gpt-4.1 / hermes-agent',
                                ),
                              );
                              if (narrow) {
                                return Column(
                                  children: [
                                    provider,
                                    const SizedBox(height: PMSpacing.l),
                                    model,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: provider),
                                  const SizedBox(width: PMSpacing.l),
                                  Expanded(child: model),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: PMSpacing.l),
                          _buildCredentialVaultSection(),
                          const SizedBox(height: PMSpacing.l),
                          TextFormField(
                            controller: _promptController,
                            minLines: 5,
                            maxLines: 10,
                            decoration: const InputDecoration(
                              labelText: '系统提示词',
                              alignLabelWithHint: true,
                              prefixIcon: Icon(Icons.notes),
                            ),
                          ),
                          const SizedBox(height: PMSpacing.l),
                          _buildCharacterCardSection(),
                          const SizedBox(height: PMSpacing.l),
                          TextFormField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: _isEditing
                                  ? '新 API Key（留空则保留当前凭据）'
                                  : '新 API Key（可选，保存后进入凭据保险箱）',
                              prefixIcon: const Icon(Icons.key),
                              helperText: '不会回显明文；填写后会加密保存到 Provider Vault。',
                            ),
                          ),
                          const SizedBox(height: PMSpacing.xl),
                          _buildSlider(
                            label: 'Temperature',
                            value: _temperature,
                            display: _temperature.toStringAsFixed(1),
                            min: 0,
                            max: 2,
                            divisions: 20,
                            onChanged: (value) =>
                                setState(() => _temperature = value),
                          ),
                          const SizedBox(height: PMSpacing.l),
                          _buildSlider(
                            label: 'Max Tokens',
                            value: _maxTokens.toDouble(),
                            display: _maxTokens.toString(),
                            min: 256,
                            max: 8192,
                            divisions: 31,
                            onChanged: (value) =>
                                setState(() => _maxTokens = value.round()),
                          ),
                          const SizedBox(height: PMSpacing.xl),
                          Align(
                            alignment: Alignment.centerRight,
                            child: PMButton(
                              label: _isEditing ? '保存 Bot' : '创建 Bot',
                              icon: Icons.check,
                              loading: _saving,
                              onPressed: _save,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCharacterCardSection() {
    final disabled = !_isEditing || _characterBusy;
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_stories, color: AppColors.primary),
              const SizedBox(width: PMSpacing.s),
              const Expanded(
                child: Text(
                  'SillyTavern v2 角色卡',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              PMChip(
                label: _hasCharacterCard ? '已导入' : '未导入',
                icon: _hasCharacterCard ? Icons.check : Icons.info_outline,
                selected: _hasCharacterCard,
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.s),
          const Text(
            '导入角色 persona、场景、开场白、替代问候和角色书关键词，用于 Bot 回复前的 prompt 组装。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.m),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              PMButton(
                label: '导入 JSON',
                icon: Icons.upload_file,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: disabled ? null : _showImportCharacterCardDialog,
              ),
              PMButton(
                label: '导出 JSON',
                icon: Icons.download,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: disabled ? null : _showExportCharacterCardDialog,
              ),
              if (!_isEditing)
                const Text(
                  '先创建 Bot 后可导入角色卡。',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
            ],
          ),
          if (_characterPersona?.trim().isNotEmpty == true) ...[
            const SizedBox(height: PMSpacing.m),
            _buildCharacterPreviewRow('Persona', _characterPersona!),
          ],
          if (_characterScenario?.trim().isNotEmpty == true)
            _buildCharacterPreviewRow('场景', _characterScenario!),
          if (_characterFirstMes?.trim().isNotEmpty == true)
            _buildCharacterPreviewRow('开场白', _characterFirstMes!),
          if (_alternateGreetings.isNotEmpty)
            _buildCharacterPreviewRow(
              '替代问候',
              _alternateGreetings.take(3).join(' / '),
            ),
          if (_bookEntryCount > 0)
            _buildCharacterPreviewRow('角色书', '$_bookEntryCount 条关键词条目'),
        ],
      ),
    );
  }

  Widget _buildCharacterPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: PMSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.secondaryDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialVaultSection() {
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, color: AppColors.primary),
              SizedBox(width: PMSpacing.s),
              Text(
                'Provider Vault',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.s),
          Text(
            _loadingCredentials
                ? '正在加载凭据...'
                : '选择已保存凭据，或在下方输入新 API Key 创建加密凭据。',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.m),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              PMChip(
                label: '环境默认 / 新 Key',
                icon: Icons.vpn_key_outlined,
                selected: _selectedCredentialId == null,
                onTap: () => setState(() => _selectedCredentialId = null),
              ),
              for (final credential in _credentials)
                PMChip(
                  label: '${credential.label}'
                      '${credential.secretLast4 == null ? '' : ' · ****${credential.secretLast4}'}',
                  icon: Icons.lock_outline,
                  selected: _selectedCredentialId == credential.id,
                  onTap: () => setState(
                    () => _selectedCredentialId = credential.id,
                  ),
                ),
            ],
          ),
          if (widget.bot?.providerCredentialLabel != null) ...[
            const SizedBox(height: PMSpacing.s),
            Text(
              '当前 Bot 使用: ${widget.bot!.providerCredentialLabel}'
              '${widget.bot!.providerCredentialLast4 == null ? '' : ' · ****${widget.bot!.providerCredentialLast4}'}',
              style: const TextStyle(
                color: AppColors.secondaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required String display,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      padding: const EdgeInsets.fromLTRB(
          PMSpacing.l, PMSpacing.m, PMSpacing.l, PMSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                display,
                style: const TextStyle(
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final config = BotConfig(
      id: widget.bot?.id,
      botName: _nameController.text.trim(),
      llmProvider: _providerController.text.trim(),
      modelName: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
      systemPrompt: _promptController.text.trim().isEmpty
          ? null
          : _promptController.text.trim(),
      temperature: _temperature,
      maxTokens: _maxTokens,
      isActive: widget.bot?.isActive ?? true,
      providerCredentialId: _selectedCredentialId,
    );

    try {
      if (_isEditing) {
        await _botService.updateBot(
          widget.bot!.id!,
          config,
          apiKey: _apiKeyController.text.trim().isEmpty
              ? null
              : _apiKeyController.text.trim(),
        );
      } else {
        await _botService.createBot(
          config,
          apiKey: _apiKeyController.text.trim().isEmpty
              ? null
              : _apiKeyController.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showImportCharacterCardDialog() async {
    final controller = TextEditingController();
    final jsonText = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: PMCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '导入 SillyTavern v2 角色卡',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: PMSpacing.m),
                TextField(
                  controller: controller,
                  minLines: 12,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    hintText: '{"spec":"chara_card_v2","data":{...}}',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: PMSpacing.l),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PMButton(
                      label: '取消',
                      compact: true,
                      variant: PMButtonVariant.secondary,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: PMSpacing.s),
                    PMButton(
                      label: '导入',
                      compact: true,
                      icon: Icons.upload_file,
                      onPressed: () => Navigator.pop(context, controller.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (jsonText == null || jsonText.trim().isEmpty || widget.bot?.id == null) {
      return;
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('角色卡必须是 JSON Object');
      }
      setState(() => _characterBusy = true);
      final bot =
          await _botService.importCharacterCard(widget.bot!.id!, decoded);
      if (!mounted) return;
      setState(() {
        _hasCharacterCard = bot.hasCharacterCard;
        _characterPersona = bot.characterPersona;
        _characterScenario = bot.characterScenario;
        _characterFirstMes = bot.characterFirstMes;
        _alternateGreetings = bot.characterAlternateGreetings;
        _bookEntryCount = bot.characterBookEntryCount;
        _nameController.text = bot.botName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角色卡已导入')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $error')),
      );
    } finally {
      if (mounted) setState(() => _characterBusy = false);
    }
  }

  Future<void> _showExportCharacterCardDialog() async {
    if (widget.bot?.id == null) return;
    setState(() => _characterBusy = true);
    try {
      final card = await _botService.exportCharacterCard(widget.bot!.id!);
      if (!mounted) return;
      final text = const JsonEncoder.withIndent('  ').convert(card);
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: PMCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '导出角色卡 JSON',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: PMSpacing.m),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 460),
                    child: SingleChildScrollView(
                      child: SelectableText(text),
                    ),
                  ),
                  const SizedBox(height: PMSpacing.l),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PMButton(
                      label: '关闭',
                      compact: true,
                      variant: PMButtonVariant.secondary,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $error')),
      );
    } finally {
      if (mounted) setState(() => _characterBusy = false);
    }
  }

  Future<void> _loadCredentialsForProvider() async {
    final provider = _providerController.text.trim();
    if (provider.isEmpty || !mounted) return;
    setState(() => _loadingCredentials = true);
    try {
      final credentials =
          await _botService.getProviderCredentials(provider: provider);
      if (!mounted) return;
      setState(() {
        _credentials = credentials;
        if (_selectedCredentialId != null &&
            !credentials.any((item) => item.id == _selectedCredentialId)) {
          _selectedCredentialId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _credentials = const []);
    } finally {
      if (mounted) setState(() => _loadingCredentials = false);
    }
  }
}
