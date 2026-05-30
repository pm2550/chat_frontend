class ChatCustomizationOption {
  const ChatCustomizationOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

class ChatCustomizationCatalog {
  static const defaultBackground = 'cloud_gradient';
  static const defaultAvatarFrame = 'none';
  static const defaultBubbleStyle = 'default_gradient';
  static const defaultSolidBackground = 'solid:#EAF4FF';

  static const backgrounds = [
    ChatCustomizationOption(
      id: 'cloud_gradient',
      label: '云端渐变',
      description: '清爽蓝绿渐变，适合日常办公聊天。',
    ),
    ChatCustomizationOption(
      id: 'pixel_mint',
      label: '像素薄荷',
      description: '细点阵和浅绿色，延续 PM chat 品牌感。',
    ),
    ChatCustomizationOption(
      id: 'sunset_warm',
      label: '落日晚霞',
      description: '暖色低饱和背景，适合轻松群聊。',
    ),
    ChatCustomizationOption(
      id: 'cyber_dark',
      label: '赛博暗纹',
      description: '深色网格，仅用于背景层，文字区仍保留可读蒙版。',
    ),
    ChatCustomizationOption(
      id: 'paper_dotted',
      label: '纸张圆点',
      description: '白底细点，适合高密度消息阅读。',
    ),
    ChatCustomizationOption(
      id: 'gradient_wave',
      label: '流动波纹',
      description: '柔和波形线条，给聊天区一点动势。',
    ),
    ChatCustomizationOption(
      id: 'mono_lines',
      label: '单色线稿',
      description: '灰蓝细线，克制、安静、不抢内容。',
    ),
    ChatCustomizationOption(
      id: 'aurora',
      label: '极光',
      description: '青绿和紫色的轻量渐变叠加。',
    ),
  ];

  static const avatarFrames = [
    ChatCustomizationOption(
      id: 'none',
      label: '无边框',
      description: '保持默认头像样式。',
    ),
    ChatCustomizationOption(
      id: 'pixel_pink',
      label: '像素粉',
      description: '四角像素点缀。',
    ),
    ChatCustomizationOption(
      id: 'golden_ring',
      label: '金色圆环',
      description: '低调金色描边。',
    ),
    ChatCustomizationOption(
      id: 'starry_night',
      label: '星夜',
      description: '深蓝外圈和小星点。',
    ),
    ChatCustomizationOption(
      id: 'mint_minimal',
      label: '薄荷极简',
      description: '青绿色细框。',
    ),
    ChatCustomizationOption(
      id: 'flame',
      label: '火焰',
      description: '暖色角标强调。',
    ),
    ChatCustomizationOption(
      id: 'cyber_glow',
      label: '赛博辉光',
      description: '蓝紫霓虹外发光。',
    ),
    ChatCustomizationOption(
      id: 'retro_dashes',
      label: '复古短线',
      description: '外圈短虚线装饰。',
    ),
  ];

  static const bubbleStyles = [
    ChatCustomizationOption(
      id: 'default_gradient',
      label: '默认渐变',
      description: 'PM chat 默认蓝绿发送气泡。',
    ),
    ChatCustomizationOption(
      id: 'minimal_flat',
      label: '极简平面',
      description: '纯色、轻阴影、信息密度更高。',
    ),
    ChatCustomizationOption(
      id: 'rounded_soft',
      label: '柔和圆角',
      description: '更大的圆角和轻柔投影。',
    ),
    ChatCustomizationOption(
      id: 'retro_block',
      label: '复古块面',
      description: '方正边缘和像素感描边。',
    ),
    ChatCustomizationOption(
      id: 'dark_night',
      label: '夜间深色',
      description: '仅影响自己发送的气泡，不改变别人消息。',
    ),
    ChatCustomizationOption(
      id: 'high_contrast',
      label: '高对比',
      description: '黑白强对比，适合投影和弱光环境。',
    ),
  ];

  static bool isSolidBackground(String? id) {
    final value = id?.trim();
    if (value == null) return false;
    return RegExp(r'^solid:#[0-9A-Fa-f]{6}$').hasMatch(value);
  }

  static bool isValidBackground(String? id) =>
      isSolidBackground(id) || backgrounds.any((option) => option.id == id);

  static bool isValidAvatarFrame(String? id) =>
      avatarFrames.any((option) => option.id == id);

  static bool isValidBubbleStyle(String? id) =>
      bubbleStyles.any((option) => option.id == id);
}
