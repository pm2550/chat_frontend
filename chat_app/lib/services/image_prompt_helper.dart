import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 画图的提示词扩写档位（对应服务器 GenerateRequest.promptHelper）。
enum ImagePromptHelper {
  off('off', '关闭', '按你写的原文出图'),
  low('low', '仅翻译', '只把描述翻译给画图模型，不改写'),
  medium('medium', '创意扩写', '自动补充细节和画面感（默认）');

  const ImagePromptHelper(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;
  final String description;

  static ImagePromptHelper? fromApiValue(String? value) {
    for (final level in values) {
      if (level.apiValue == value) return level;
    }
    return null;
  }
}

/// 本机记住上次选的扩写档位；/画图、"AI 图片"面板、AI 中心画图共用同一个选择。
/// 启动时和选择控件出现时读一次，发请求时直接用 [current]（不在发送路径上等存储）。
class ImagePromptHelperPreference {
  ImagePromptHelperPreference._();

  static const String prefsKey = 'image_prompt_helper';
  static const ImagePromptHelper defaultLevel = ImagePromptHelper.medium;

  static final ValueNotifier<ImagePromptHelper> current =
      ValueNotifier(defaultLevel);
  static Future<void>? _loading;
  static bool _chosenBeforeLoad = false;

  /// 读一次本机保存的选择（之后直接用内存里的）。读不到就用默认的创意扩写。
  static Future<ImagePromptHelper> load() async {
    await (_loading ??= _read());
    return current.value;
  }

  static Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = ImagePromptHelper.fromApiValue(prefs.getString(prefsKey));
      // 读的时候用户已经点过了：以刚点的为准。
      if (stored != null && !_chosenBeforeLoad) current.value = stored;
    } catch (_) {
      // 没有本地存储（测试、隐私模式）：这次会话照样用内存里的选择。
    }
  }

  static Future<void> set(ImagePromptHelper level) async {
    _chosenBeforeLoad = true;
    current.value = level;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, level.apiValue);
    } catch (_) {
      // 存不下来也不影响这次的选择。
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _loading = null;
    _chosenBeforeLoad = false;
    current.value = defaultLevel;
  }
}
