import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/bot_service.dart';
import '../../widgets/pm_brand.dart';
import 'widgets/bot_image_provider_section.dart';

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

class _ProviderOption {
  const _ProviderOption({
    required this.value,
    required this.label,
    required this.defaultModel,
    required this.icon,
  });

  final String value;
  final String label;
  final String defaultModel;
  final IconData icon;
}

class _BotEditScreenState extends State<BotEditScreen> {
  static const List<_ProviderOption> _providerOptions = [
    _ProviderOption(
      value: 'HERMES',
      label: 'Hermes / Grok',
      defaultModel: 'grok-4.3',
      icon: Icons.auto_awesome,
    ),
    _ProviderOption(
      value: 'OPENAI',
      label: 'OpenAI',
      defaultModel: 'gpt-4.1',
      icon: Icons.blur_on,
    ),
    _ProviderOption(
      value: 'CLAUDE',
      label: 'Claude',
      defaultModel: 'claude-3-5-sonnet',
      icon: Icons.hexagon_outlined,
    ),
    _ProviderOption(
      value: 'DEEPSEEK',
      label: 'DeepSeek',
      defaultModel: 'deepseek-chat',
      icon: Icons.water,
    ),
    _ProviderOption(
      value: 'OLLAMA',
      label: 'Ollama',
      defaultModel: 'kimi-k2.6',
      icon: Icons.dns_outlined,
    ),
    _ProviderOption(
      value: 'DASHSCOPE',
      label: 'DashScope',
      defaultModel: 'qwen-plus',
      icon: Icons.cloud_queue,
    ),
    _ProviderOption(
      value: 'KIMI',
      label: 'Kimi Code',
      defaultModel: 'kimi-code',
      icon: Icons.code,
    ),
  ];

  late final BotService _botService;
  late final TextEditingController _nameController;
  late final TextEditingController _providerController;
  late final TextEditingController _modelController;
  late final TextEditingController _promptController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _allowedUsersController;
  late final TextEditingController _imageApiKeyController;
  late final TextEditingController _imageEndpointController;
  late final TextEditingController _imageModelController;
  late final TextEditingController _imageNegativePromptController;

  final _formKey = GlobalKey<FormState>();
  double _temperature = 0.7;
  int _maxTokens = 2048;
  int _maxHistoryMessages = 20;
  bool _includeRoomMetadata = true;
  bool _visionInputEnabled = true;
  bool _historyImageInspectionEnabled = true;
  bool _webSearchEnabled = false;
  bool _imageGenerationEnabled = false;
  String _replyMode = 'SINGLE';
  String _accessPolicy = 'PRIVATE';
  bool _saving = false;
  bool _loadingCredentials = false;
  bool _characterBusy = false;
  List<ProviderCredential> _credentials = const [];
  List<ProviderCredential> _imageCredentials = const [];
  int? _selectedCredentialId;
  int? _selectedImageCredentialId;
  String _imageProvider = 'HERMES';
  bool _loadingImageCredentials = false;
  bool _hasCharacterCard = false;
  String? _characterPersona;
  String? _characterScenario;
  String? _characterFirstMes;
  List<String> _alternateGreetings = const [];
  int _bookEntryCount = 0;
  PickedBotAvatar? _selectedAvatar;
  Uint8List? _avatarPreviewBytes;
  String? _botAvatarUrl;

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
    _imageApiKeyController = TextEditingController();
    _imageEndpointController = TextEditingController();
    _imageModelController = TextEditingController(text: bot?.imageModel ?? '');
    _imageNegativePromptController =
        TextEditingController(text: bot?.imageNegativePrompt ?? '');
    _allowedUsersController = TextEditingController(
      text: bot?.allowedUsers
              .map((user) =>
                  user.username.isNotEmpty ? user.username : user.id.toString())
              .join(', ') ??
          '',
    );
    _botAvatarUrl = bot?.botAvatar;
    _webSearchEnabled = bot?.enabledTools.contains('web_search') ?? false;
    _imageGenerationEnabled =
        bot?.enabledTools.contains('generate_image') ?? false;
    _imageProvider = bot?.imageGenerationProvider ?? 'HERMES';
    _selectedImageCredentialId = bot?.imageProviderCredentialId;
    _replyMode = (bot?.replyMode ?? 'SINGLE').toUpperCase();
    _accessPolicy = bot?.accessPolicy ?? 'PRIVATE';
    _providerController.addListener(_loadCredentialsForProvider);
    _temperature = bot?.temperature ?? 0.7;
    _maxTokens = bot?.maxTokens ?? 2048;
    _maxHistoryMessages = bot?.maxHistoryMessages ?? 20;
    _includeRoomMetadata = bot?.includeRoomMetadata ?? true;
    _visionInputEnabled = bot?.visionInputEnabled ?? true;
    _historyImageInspectionEnabled = bot?.historyImageInspectionEnabled ?? true;
    _selectedCredentialId = bot?.providerCredentialId;
    _hasCharacterCard = bot?.hasCharacterCard ?? false;
    _characterPersona = bot?.characterPersona;
    _characterScenario = bot?.characterScenario;
    _characterFirstMes = bot?.characterFirstMes;
    _alternateGreetings = bot?.characterAlternateGreetings ?? const [];
    _bookEntryCount = bot?.characterBookEntryCount ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCredentialsForProvider();
      _loadImageCredentials();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    _apiKeyController.dispose();
    _allowedUsersController.dispose();
    _imageApiKeyController.dispose();
    _imageEndpointController.dispose();
    _imageModelController.dispose();
    _imageNegativePromptController.dispose();
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
                          _buildAvatarSection(),
                          const SizedBox(height: PMSpacing.l),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 620;
                              final provider = _buildProviderPicker();
                              final model = TextFormField(
                                controller: _modelController,
                                decoration: const InputDecoration(
                                  labelText: '模型名',
                                  prefixIcon: Icon(Icons.memory),
                                  hintText: '例如 grok-4.3 / gpt-4.1',
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
                          const SizedBox(height: PMSpacing.l),
                          _buildReplyModeSection(),
                          const SizedBox(height: PMSpacing.l),
                          _buildContextSection(),
                          const SizedBox(height: PMSpacing.l),
                          _buildToolTogglesSection(),
                          if (_imageGenerationEnabled) ...[
                            const SizedBox(height: PMSpacing.l),
                            BotImageProviderSection(
                              provider: _imageProvider,
                              credentials: _imageCredentials,
                              selectedCredentialId: _selectedImageCredentialId,
                              loadingCredentials: _loadingImageCredentials,
                              apiKeyController: _imageApiKeyController,
                              endpointController: _imageEndpointController,
                              modelController: _imageModelController,
                              negativePromptController:
                                  _imageNegativePromptController,
                              currentCredentialLabel:
                                  widget.bot?.imageProviderCredentialLabel,
                              currentCredentialLast4:
                                  widget.bot?.imageProviderCredentialLast4,
                              onProviderChanged: _setImageProvider,
                              onCredentialChanged: _selectImageCredential,
                            ),
                          ],
                          const SizedBox(height: PMSpacing.l),
                          _buildAccessPolicySection(),
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

  Widget _buildProviderPicker() {
    final selected = _providerController.text.trim().toUpperCase();
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      padding: const EdgeInsets.all(PMSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_queue, size: 20, color: AppColors.primary),
              SizedBox(width: PMSpacing.s),
              Text(
                'LLM Provider',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.s),
          const Text(
            '选择模型供应商，不需要手填枚举名。Hermes/Grok 支持当前 Agent 工具调用。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: PMSpacing.m),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              for (final option in _providerOptions)
                PMChip(
                  label: option.label,
                  icon: option.icon,
                  selected: selected == option.value,
                  onTap: () => _setProvider(option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection() {
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      padding: const EdgeInsets.all(PMSpacing.m),
      child: Row(
        children: [
          _buildAvatarPreview(),
          const SizedBox(width: PMSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bot 头像',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedAvatar != null
                      ? '已选择 ${_selectedAvatar!.name}，保存后上传。'
                      : (_botAvatarUrl?.trim().isNotEmpty == true
                          ? '当前头像会用于聊天气泡和 Bot 列表。'
                          : '未设置头像，聊天里会显示默认 Bot 图标。'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: PMSpacing.s),
                Wrap(
                  spacing: PMSpacing.s,
                  runSpacing: PMSpacing.s,
                  children: [
                    PMButton(
                      label: '选择头像',
                      icon: Icons.image_outlined,
                      compact: true,
                      variant: PMButtonVariant.secondary,
                      onPressed: _saving ? null : _pickBotAvatar,
                    ),
                    if (_selectedAvatar != null)
                      PMButton(
                        label: '取消选择',
                        icon: Icons.close,
                        compact: true,
                        variant: PMButtonVariant.link,
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  _selectedAvatar = null;
                                  _avatarPreviewBytes = null;
                                }),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPreview() {
    final bytes = _avatarPreviewBytes;
    final avatarUrl = _botAvatarUrl?.trim();
    Widget child;
    if (bytes != null && bytes.isNotEmpty) {
      child = Image.memory(bytes, fit: BoxFit.cover);
    } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
      child = Image.network(
        ApiConstants.resolveFileUrl(avatarUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _BotAvatarFallback(),
      );
    } else {
      child = const _BotAvatarFallback();
    }

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.pixelBlue,
        borderRadius: BorderRadius.circular(PMRadius.m),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Future<void> _pickBotAvatar() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 90,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedAvatar = PickedBotAvatar(
          name: image.name,
          path: image.path,
          bytes: bytes,
          size: bytes.length,
          mimeType: image.mimeType,
        );
        _avatarPreviewBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择头像失败: $error')),
      );
    }
  }

  Widget _buildReplyModeSection() {
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.chat_bubble_outline, color: AppColors.primary),
              SizedBox(width: PMSpacing.s),
              Expanded(
                child: Text(
                  '说话模式',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.s),
          const Text(
            '控制 Bot 回复时是一整段发出，还是像 QQ Bot/阿雷那样按句子连续发出。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.m),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              PMChip(
                key: const Key('bot-reply-mode-single'),
                label: '整段回复',
                icon: Icons.subject,
                selected: _replyMode == 'SINGLE',
                onTap: () => setState(() => _replyMode = 'SINGLE'),
              ),
              PMChip(
                key: const Key('bot-reply-mode-chunked'),
                label: '一句一句说',
                icon: Icons.chat_bubble_outline,
                selected: _replyMode == 'CHUNKED',
                onTap: () => setState(() => _replyMode = 'CHUNKED'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContextSection() {
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.group, color: AppColors.primary),
              SizedBox(width: PMSpacing.s),
              Expanded(
                child: Text(
                  '群聊上下文',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.s),
          const Text(
            '默认开启。开启后，Bot 会知道自己所在房间、成员概况和最近聊天，不会像孤立 API 一样只看当前一句。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.m),
          _buildToolRow(
            icon: Icons.chat_bubble_outline,
            title: '注入房间和成员信息',
            subtitle: '让 Bot 知道房间名、成员、自己在本群的昵称；关闭后仍保留基本系统提示。',
            value: _includeRoomMetadata,
            key: const Key('bot-edit-room-context-switch'),
            onChanged: (value) => setState(() => _includeRoomMetadata = value),
          ),
          const Divider(height: PMSpacing.l),
          Row(
            children: [
              const Icon(Icons.history, size: 20, color: AppColors.secondary),
              const SizedBox(width: PMSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '最近消息条数',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '当前会把最近 $_maxHistoryMessages 条消息放进上下文。',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$_maxHistoryMessages',
                style: const TextStyle(
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Slider(
            value: _maxHistoryMessages.toDouble().clamp(0, 60),
            min: 0,
            max: 60,
            divisions: 12,
            label: '$_maxHistoryMessages',
            onChanged: (value) =>
                setState(() => _maxHistoryMessages = value.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildToolTogglesSection() {
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.extension, color: AppColors.primary),
              const SizedBox(width: PMSpacing.s),
              const Expanded(
                child: Text(
                  'Bot 能力',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              PMButton(
                label: '设为画图 Bot',
                icon: Icons.image_outlined,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: _applyImageBotPreset,
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.s),
          const Text(
            '开启工具后，Bot 被 @ 或关键词触发时会走多轮 Agent，并按白名单调用这些能力。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.m),
          _buildToolRow(
            icon: Icons.travel_explore,
            title: '联网搜索',
            subtitle: 'web_search · 通过自建 SearXNG 检索网页。',
            value: _webSearchEnabled,
            key: const Key('bot-edit-web-search-switch'),
            onChanged: (value) => setState(() => _webSearchEnabled = value),
          ),
          const Divider(height: PMSpacing.l),
          _buildToolRow(
            icon: Icons.visibility_outlined,
            title: '允许视觉输入',
            subtitle: '图片始终交给这个 Bot 自己配置的模型，不会切换到其他视觉模型。',
            value: _visionInputEnabled,
            key: const Key('bot-edit-vision-input-switch'),
            onChanged: (value) => setState(() {
              _visionInputEnabled = value;
              if (!value) _historyImageInspectionEnabled = false;
            }),
          ),
          const Divider(height: PMSpacing.l),
          _buildToolRow(
            icon: Icons.image_search_outlined,
            title: '主动查看历史图片',
            subtitle:
                'inspect_room_image · Bot 可按消息 ID 或最近顺序读取本房间图片，再由自己的模型分析。',
            value: _visionInputEnabled && _historyImageInspectionEnabled,
            key: const Key('bot-edit-history-image-switch'),
            onChanged: _visionInputEnabled
                ? (value) =>
                    setState(() => _historyImageInspectionEnabled = value)
                : (_) {},
          ),
          const Divider(height: PMSpacing.l),
          _buildToolRow(
            icon: Icons.image_outlined,
            title: 'AI 画图',
            subtitle:
                'generate_image · 可选平台 Hermes 或 Bot 自己的图片 API，图片以 Bot 身份发回会话。',
            value: _imageGenerationEnabled,
            key: const Key('bot-edit-image-generation-switch'),
            onChanged: (value) =>
                setState(() => _imageGenerationEnabled = value),
          ),
        ],
      ),
    );
  }

  Widget _buildToolRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Key key,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.secondary),
        const SizedBox(width: PMSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Switch(
          key: key,
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildAccessPolicySection() {
    return PMCard(
      elevated: false,
      background: AppColors.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined,
                  color: AppColors.primary),
              SizedBox(width: PMSpacing.s),
              Expanded(
                child: Text(
                  '使用权限',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.s),
          const Text(
            '控制谁可以把这个 Bot 加进房间、谁可以在房间里触发它。创建者始终拥有完整权限。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.m),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              PMChip(
                key: const Key('bot-access-private'),
                label: '仅自己',
                icon: Icons.lock_outline,
                selected: _accessPolicy == 'PRIVATE',
                onTap: () => setState(() => _accessPolicy = 'PRIVATE'),
              ),
              PMChip(
                key: const Key('bot-access-allowlist'),
                label: '指定用户',
                icon: Icons.group_add_outlined,
                selected: _accessPolicy == 'ALLOWLIST',
                onTap: () => setState(() => _accessPolicy = 'ALLOWLIST'),
              ),
              PMChip(
                key: const Key('bot-access-public'),
                label: '房间成员可用',
                icon: Icons.public,
                selected: _accessPolicy == 'PUBLIC',
                onTap: () => setState(() => _accessPolicy = 'PUBLIC'),
              ),
            ],
          ),
          if (_accessPolicy == 'ALLOWLIST') ...[
            const SizedBox(height: PMSpacing.m),
            TextFormField(
              key: const Key('bot-access-allowed-users-field'),
              controller: _allowedUsersController,
              decoration: const InputDecoration(
                labelText: '允许使用者',
                hintText: '用户名或用户 ID，用逗号分隔，例如 admin, user, 42',
                prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                helperText: '这些用户可把 Bot 加到自己管理的房间，也可在已加入房间中触发它。',
              ),
            ),
          ],
          if (_accessPolicy == 'PUBLIC') ...[
            const SizedBox(height: PMSpacing.s),
            const Text(
              '公开后，房间管理员可以把它加入房间；加入后该房间成员都可触发。',
              style: TextStyle(color: AppColors.secondaryDark),
            ),
          ],
        ],
      ),
    );
  }

  void _setProvider(_ProviderOption option) {
    setState(() {
      _providerController.text = option.value;
      if (_modelController.text.trim().isEmpty ||
          _providerOptions
              .map((candidate) => candidate.defaultModel)
              .contains(_modelController.text.trim())) {
        _modelController.text = option.defaultModel;
      }
    });
  }

  void _applyImageBotPreset() {
    const drawPrompt = '''
你是 PM chat 的画图 Bot。用户让你画图、生成图片、做插画、改成某种画面风格时，先提取清晰的画面描述，然后调用 generate_image 工具。

规则：
- 不要假装已经画完；工具提交成功后告诉用户图片正在生成。
- 如果用户没有说明比例，默认 1:1。
- 如果用户要求快一点，可以把 expand 设为 false；否则默认 expand true。
- 如果不是画图请求，正常简短回复。''';
    setState(() {
      final hermes =
          _providerOptions.firstWhere((option) => option.value == 'HERMES');
      _providerController.text = hermes.value;
      _modelController.text = hermes.defaultModel;
      _imageGenerationEnabled = true;
      if (_promptController.text.trim().isEmpty) {
        _promptController.text = drawPrompt.trim();
      }
    });
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
    if (_imageGenerationEnabled &&
        _imageProvider != 'HERMES' &&
        _selectedImageCredentialId == null &&
        _imageApiKeyController.text.trim().isEmpty &&
        widget.bot?.hasImageProviderCredential != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择画图凭据或填写图片 API Key')),
      );
      return;
    }
    if (_imageGenerationEnabled &&
        _imageProvider == 'OPENAI_COMPATIBLE' &&
        _selectedImageCredentialId == null &&
        _imageEndpointController.text.trim().isEmpty &&
        widget.bot?.hasImageProviderCredential != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写 OpenAI 兼容图片 API 的 Base URL')),
      );
      return;
    }
    setState(() => _saving = true);
    final config = BotConfig(
      id: widget.bot?.id,
      botName: _nameController.text.trim(),
      botAvatar: _botAvatarUrl,
      llmProvider: _providerController.text.trim(),
      modelName: _modelController.text.trim().isEmpty
          ? null
          : _modelController.text.trim(),
      systemPrompt: _promptController.text.trim().isEmpty
          ? null
          : _promptController.text.trim(),
      temperature: _temperature,
      maxTokens: _maxTokens,
      maxHistoryMessages: _maxHistoryMessages,
      includeRoomMetadata: _includeRoomMetadata,
      visionInputEnabled: _visionInputEnabled,
      historyImageInspectionEnabled: _historyImageInspectionEnabled,
      replyMode: _replyMode,
      isActive: widget.bot?.isActive ?? true,
      enabledTools: _composeEnabledTools(),
      accessPolicy: _accessPolicy,
      allowedUsernames:
          _accessPolicy == 'ALLOWLIST' ? _parseAllowedUsers() : const [],
      providerCredentialId: _selectedCredentialId,
      imageGenerationProvider: _imageProvider,
      imageProviderCredentialId: _selectedImageCredentialId,
      imageModel: _imageModelController.text.trim().isEmpty
          ? null
          : _imageModelController.text.trim(),
      imageNegativePrompt: _imageNegativePromptController.text.trim().isEmpty
          ? null
          : _imageNegativePromptController.text.trim(),
    );

    try {
      BotConfig? saved;
      if (_isEditing) {
        saved = await _botService.updateBot(
          widget.bot!.id!,
          config,
          apiKey: _apiKeyController.text.trim().isEmpty
              ? null
              : _apiKeyController.text.trim(),
          imageApiKey: _imageApiKeyController.text.trim().isEmpty
              ? null
              : _imageApiKeyController.text.trim(),
          imageBaseUrl: _imageEndpointController.text.trim().isEmpty
              ? null
              : _imageEndpointController.text.trim(),
        );
      } else {
        saved = await _botService.createBot(
          config,
          apiKey: _apiKeyController.text.trim().isEmpty
              ? null
              : _apiKeyController.text.trim(),
          imageApiKey: _imageApiKeyController.text.trim().isEmpty
              ? null
              : _imageApiKeyController.text.trim(),
          imageBaseUrl: _imageEndpointController.text.trim().isEmpty
              ? null
              : _imageEndpointController.text.trim(),
        );
      }
      final avatar = _selectedAvatar;
      final botId = saved?.id;
      if (avatar != null && botId != null) {
        saved = await _botService.uploadBotAvatar(botId, avatar);
      }
      if (!mounted) return;
      setState(() {
        _botAvatarUrl = saved?.botAvatar ?? _botAvatarUrl;
        _selectedAvatar = null;
        _avatarPreviewBytes = null;
      });
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

  // Preserve any other tools the bot already has; only flip tools controlled here.
  List<String> _composeEnabledTools() {
    final tools = <String>{...?widget.bot?.enabledTools};
    if (_webSearchEnabled) {
      tools.add('web_search');
    } else {
      tools.remove('web_search');
    }
    if (_imageGenerationEnabled) {
      tools.add('generate_image');
    } else {
      tools.remove('generate_image');
    }
    if (_visionInputEnabled && _historyImageInspectionEnabled) {
      tools.add('inspect_room_image');
    } else {
      tools.remove('inspect_room_image');
    }
    return tools.toList(growable: false);
  }

  List<String> _parseAllowedUsers() {
    return _allowedUsersController.text
        .split(RegExp(r'[,，\s]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
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

  void _setImageProvider(String provider) {
    setState(() {
      _imageProvider = provider;
      _selectedImageCredentialId = null;
      _imageCredentials = const [];
      if (provider == 'NOVELAI') {
        _imageEndpointController.text =
            'https://image.novelai.net/ai/generate-image';
        if (_imageModelController.text.trim().isEmpty ||
            _imageModelController.text == 'gpt-image-1') {
          _imageModelController.text = 'nai-diffusion-3';
        }
      } else if (provider == 'OPENAI_COMPATIBLE') {
        _imageEndpointController.clear();
        if (_imageModelController.text.trim().isEmpty ||
            _imageModelController.text == 'nai-diffusion-3') {
          _imageModelController.text = 'gpt-image-1';
        }
      }
    });
    _loadImageCredentials();
  }

  void _selectImageCredential(int? credentialId) {
    setState(() {
      _selectedImageCredentialId = credentialId;
      if (credentialId == null) return;
      ProviderCredential? credential;
      for (final item in _imageCredentials) {
        if (item.id == credentialId) {
          credential = item;
          break;
        }
      }
      if (credential == null) return;
      _imageEndpointController.text = credential.baseUrl ?? '';
      if (credential.modelOverride?.isNotEmpty == true) {
        _imageModelController.text = credential.modelOverride!;
      }
      _imageApiKeyController.clear();
    });
  }

  Future<void> _loadImageCredentials() async {
    if (!mounted || _imageProvider == 'HERMES') {
      if (mounted) setState(() => _imageCredentials = const []);
      return;
    }
    setState(() => _loadingImageCredentials = true);
    try {
      final providers = _imageProvider == 'NOVELAI'
          ? const ['NOVELAI']
          : const ['IMAGE_API', 'OPENAI'];
      final batches = await Future.wait(
        providers.map(
          (provider) => _botService.getProviderCredentials(provider: provider),
        ),
      );
      if (!mounted) return;
      final credentials = batches.expand((items) => items).toList();
      setState(() {
        _imageCredentials = credentials;
        if (_selectedImageCredentialId != null &&
            !credentials.any((item) => item.id == _selectedImageCredentialId)) {
          _selectedImageCredentialId = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _imageCredentials = const []);
    } finally {
      if (mounted) setState(() => _loadingImageCredentials = false);
    }
  }
}

class _BotAvatarFallback extends StatelessWidget {
  const _BotAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: const Center(
        child: Icon(Icons.smart_toy, color: Colors.white, size: 30),
      ),
    );
  }
}
