import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../design/design.dart';
import '../../../services/bot_service.dart';

class BotImageProviderSection extends StatelessWidget {
  const BotImageProviderSection({
    super.key,
    required this.provider,
    required this.credentials,
    required this.selectedCredentialId,
    required this.loadingCredentials,
    required this.apiKeyController,
    required this.endpointController,
    required this.modelController,
    required this.negativePromptController,
    required this.promptMode,
    required this.invocationMode,
    required this.rewriteFailurePolicy,
    required this.onProviderChanged,
    required this.onCredentialChanged,
    required this.onPromptModeChanged,
    required this.onInvocationModeChanged,
    required this.onRewriteFailurePolicyChanged,
    required this.onModelChanged,
    this.currentCredentialLabel,
    this.currentCredentialLast4,
  });

  final String provider;
  final List<ProviderCredential> credentials;
  final int? selectedCredentialId;
  final bool loadingCredentials;
  final TextEditingController apiKeyController;
  final TextEditingController endpointController;
  final TextEditingController modelController;
  final TextEditingController negativePromptController;
  final String promptMode;
  final String invocationMode;
  final String rewriteFailurePolicy;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<int?> onCredentialChanged;
  final ValueChanged<String> onPromptModeChanged;
  final ValueChanged<String> onInvocationModeChanged;
  final ValueChanged<String> onRewriteFailurePolicyChanged;
  final ValueChanged<String> onModelChanged;
  final String? currentCredentialLabel;
  final String? currentCredentialLast4;

  bool get _usesOwnProvider => provider != 'HERMES';

  @override
  Widget build(BuildContext context) {
    return PMCard(
      key: const Key('bot-image-provider-section'),
      elevated: false,
      background: AppColors.cloud,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '画图模型',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: PMSpacing.xs),
          const Text(
            'Bot 先把用户要求整理成 prompt，再调用这里选择的图片 API。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.m),
          const Text(
            '调用方式',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: PMSpacing.xs),
          Text(
            invocationMode == 'DIRECT'
                ? '直接出图只跳过 Agent 的工具决策；是否转写仍由下方中文提示词模式决定。全局负面提示词始终独立发送。'
                : '智能调用由文字模型结合上下文决定是否画图，并按下面选择的提示词模式处理。',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: PMSpacing.s),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              PMChip(
                label: '智能调用',
                selected: invocationMode == 'AGENT',
                onTap: () => onInvocationModeChanged('AGENT'),
              ),
              PMChip(
                label: '直接出图',
                selected: invocationMode == 'DIRECT',
                onTap: () => onInvocationModeChanged('DIRECT'),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.m),
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              _providerChip('HERMES', '平台 Hermes'),
              _providerChip('OPENAI_COMPATIBLE', 'OpenAI 兼容'),
              _providerChip('NOVELAI', 'NovelAI'),
            ],
          ),
          if (_usesOwnProvider) ...[
            const SizedBox(height: PMSpacing.l),
            Text(
              loadingCredentials ? '正在加载画图凭据...' : '选择加密凭据，或填写新 Key。',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: PMSpacing.s),
            Wrap(
              spacing: PMSpacing.s,
              runSpacing: PMSpacing.s,
              children: [
                PMChip(
                  label: '新 Key',
                  icon: Icons.add,
                  selected: selectedCredentialId == null,
                  onTap: () => onCredentialChanged(null),
                ),
                for (final credential in credentials)
                  PMChip(
                    label: '${credential.label}'
                        '${credential.secretLast4 == null ? '' : ' · ****${credential.secretLast4}'}',
                    icon: Icons.lock_outline,
                    selected: selectedCredentialId == credential.id,
                    onTap: () => onCredentialChanged(credential.id),
                  ),
              ],
            ),
            if (currentCredentialLabel != null) ...[
              const SizedBox(height: PMSpacing.s),
              Text(
                '当前使用: $currentCredentialLabel'
                '${currentCredentialLast4 == null ? '' : ' · ****$currentCredentialLast4'}',
                style: const TextStyle(
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: PMSpacing.m),
            TextField(
              controller: apiKeyController,
              obscureText: true,
              enabled: selectedCredentialId == null,
              decoration: const InputDecoration(
                labelText: '图片 API Key',
                prefixIcon: Icon(Icons.key),
                helperText: '只在保存时发送，服务端加密存储且不会回显。',
              ),
            ),
            const SizedBox(height: PMSpacing.m),
            TextField(
              controller: endpointController,
              enabled: selectedCredentialId == null,
              decoration: InputDecoration(
                labelText: provider == 'NOVELAI'
                    ? 'NovelAI Endpoint'
                    : '图片 API Base URL / Endpoint',
                prefixIcon: const Icon(Icons.link),
                hintText: provider == 'NOVELAI'
                    ? 'https://image.novelai.net/ai/generate-image'
                    : 'https://example.com/v1',
              ),
            ),
            const SizedBox(height: PMSpacing.m),
            if (provider == 'NOVELAI') ...[
              const Text(
                'NovelAI 模型',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: PMSpacing.s),
              Wrap(
                spacing: PMSpacing.s,
                runSpacing: PMSpacing.s,
                children: [
                  _modelChip('nai-diffusion-4-5-full', 'V4.5 Full · 推荐'),
                  _modelChip('nai-diffusion-4-5-curated', 'V4.5 Curated'),
                  _modelChip('nai-diffusion-4-full', 'V4 Full'),
                  _modelChip('nai-diffusion-4-curated', 'V4 Curated'),
                  _modelChip('nai-diffusion-3', 'Anime V3 · 旧版'),
                ],
              ),
            ] else
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '图片模型',
                  prefixIcon: Icon(Icons.image_outlined),
                  hintText: 'gpt-image-1 / flux-image',
                ),
              ),
            if (provider == 'NOVELAI') ...[
              const SizedBox(height: PMSpacing.m),
              const Text(
                '中文提示词',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: PMSpacing.xs),
              const Text(
                '二次元增强会保留主体、动作、服装与暴露程度；未指定画风时补充 2D 动画线稿、赛璐璐上色和美感细节。明确要求真人或写实时仍以原意为准。',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: PMSpacing.s),
              Wrap(
                spacing: PMSpacing.s,
                runSpacing: PMSpacing.s,
                children: [
                  PMChip(
                    label: '二次元增强 · 推荐',
                    selected: promptMode == 'ANIME_CREATIVE',
                    onTap: () => onPromptModeChanged('ANIME_CREATIVE'),
                  ),
                  PMChip(
                    label: '忠实中性转写',
                    selected: promptMode == 'FAITHFUL_CREATIVE',
                    onTap: () => onPromptModeChanged('FAITHFUL_CREATIVE'),
                  ),
                  PMChip(
                    label: '原文直传',
                    selected: promptMode == 'VERBATIM',
                    onTap: () => onPromptModeChanged('VERBATIM'),
                  ),
                ],
              ),
              if (promptMode != 'VERBATIM') ...[
                const SizedBox(height: PMSpacing.m),
                const Text(
                  '润色不可用时',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: PMSpacing.xs),
                const Text(
                  '默认按用户原文继续调用 NovelAI；不会在这里替图片服务作内容判断。',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: PMSpacing.s),
                Wrap(
                  spacing: PMSpacing.s,
                  runSpacing: PMSpacing.s,
                  children: [
                    PMChip(
                      label: '按原文继续 · 推荐',
                      selected: rewriteFailurePolicy == 'USE_SOURCE_PROMPT',
                      onTap: () => onRewriteFailurePolicyChanged(
                        'USE_SOURCE_PROMPT',
                      ),
                    ),
                    PMChip(
                      label: '停止并提示',
                      selected: rewriteFailurePolicy == 'FAIL',
                      onTap: () => onRewriteFailurePolicyChanged('FAIL'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: PMSpacing.m),
              TextField(
                controller: negativePromptController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '负面提示词（可选）',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.do_not_disturb_alt_outlined),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _providerChip(String value, String label) {
    return PMChip(
      label: label,
      selected: provider == value,
      onTap: () => onProviderChanged(value),
    );
  }

  Widget _modelChip(String value, String label) {
    return PMChip(
      label: label,
      selected: modelController.text == value,
      onTap: () => onModelChanged(value),
    );
  }
}
