/// 编辑器里的采样/思考参数只在后端真正会把它发给模型时才显示。
///
/// 规则必须与后端 `LLMService` 保持一致：
/// - Temperature：OpenAI 的 gpt-5 / o1 / o3 / o4 推理模型会被后端丢掉；
///   Claude 只有 3.x 与 4 ~ 4.6 系列接受（4.7 起的新模型传了会报错，后端不发）；
///   其余 Provider（Hermes、DeepSeek、Ollama、DashScope、Kimi）都会发送。
/// - 思考强度：目前只有 Ollama 上的 kimi-k2 系列模型会带上 reasoning_effort。
library;

/// 模型名留空时后端使用的默认模型（application.yml 中的默认值）。
const Map<String, String> _serverDefaultModels = {
  'OPENAI': 'gpt-4o',
  'CLAUDE': 'claude-sonnet-4-20250514',
  'OLLAMA': 'llama3',
};

String effectiveBotModel(String provider, String model,
    {String? modelOverride}) {
  final typed = model.trim();
  if (typed.isNotEmpty) return typed.toLowerCase();
  final override = modelOverride?.trim() ?? '';
  if (override.isNotEmpty) return override.toLowerCase();
  return _serverDefaultModels[provider.trim().toUpperCase()] ?? '';
}

bool isOpenAiReasoningModel(String model) {
  final normalized = model.trim().toLowerCase();
  return normalized.startsWith('gpt-5') ||
      RegExp(r'^o[134](?:[-.].*)?$').hasMatch(normalized);
}

bool claudeAcceptsTemperature(String model) {
  var normalized = model.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  normalized = normalized.substring(normalized.lastIndexOf('/') + 1);
  return RegExp(
    r'^claude-(?:3[-.].*|(?:opus|sonnet|haiku)-4(?:-[0-6])?(?:[-@](?:\d{8}|latest))?)$',
  ).hasMatch(normalized);
}

bool botSupportsTemperature(String provider, String effectiveModel) {
  switch (provider.trim().toUpperCase()) {
    case 'OPENAI':
      return !isOpenAiReasoningModel(effectiveModel);
    case 'CLAUDE':
      return claudeAcceptsTemperature(effectiveModel);
    default:
      return true;
  }
}

/// Claude 的 temperature 范围是 0~1，其余是 0~2。
double botTemperatureMax(String provider) =>
    provider.trim().toUpperCase() == 'CLAUDE' ? 1.0 : 2.0;

bool botSupportsReasoningEffort(String provider, String effectiveModel) =>
    provider.trim().toUpperCase() == 'OLLAMA' &&
    effectiveModel.trim().toLowerCase().startsWith('kimi-k2');
