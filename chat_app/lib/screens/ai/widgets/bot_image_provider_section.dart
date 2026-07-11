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
    required this.onProviderChanged,
    required this.onCredentialChanged,
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
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<int?> onCredentialChanged;
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
                    ? 'https://api.novelai.net/ai/generate-image'
                    : 'https://example.com/v1',
              ),
            ),
            const SizedBox(height: PMSpacing.m),
            TextField(
              controller: modelController,
              decoration: InputDecoration(
                labelText: '图片模型',
                prefixIcon: const Icon(Icons.image_outlined),
                hintText: provider == 'NOVELAI'
                    ? 'nai-diffusion-3'
                    : 'gpt-image-1 / flux-image',
              ),
            ),
            if (provider == 'NOVELAI') ...[
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
}
