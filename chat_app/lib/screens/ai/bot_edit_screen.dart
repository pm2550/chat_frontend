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
    _temperature = bot?.temperature ?? 0.7;
    _maxTokens = bot?.maxTokens ?? 2048;
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
                          TextFormField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: _isEditing
                                  ? 'API Key（留空则不更新）'
                                  : 'API Key（可选）',
                              prefixIcon: const Icon(Icons.key),
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
}
