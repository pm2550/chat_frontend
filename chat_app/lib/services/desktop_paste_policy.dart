import 'chat_paste_policy.dart';

/// 桌面端（Windows/macOS/Linux）按下 Ctrl/⌘+V 后怎么处理剪贴板。
enum DesktopPasteDecision {
  /// 剪贴板里是从文件管理器复制的文件：全部排进待发送栏。
  attachFiles,

  /// 剪贴板里是图片（截图、浏览器里"复制图片"）：排进待发送栏。
  attachImage,

  /// 交还给输入框按普通文字粘贴。
  pasteText,

  /// 什么都不做。
  ignore,
}

/// 和网页版同一套规则（[decideChatPasteHandling]）：有图片就发图，
/// 除非输入框里正在粘的是一段真正的文字（比如带插图的富文本）。
DesktopPasteDecision decideDesktopPaste({
  required int fileCount,
  required bool hasImage,
  required String plainText,
  required bool textEditingFocused,
}) {
  // 复制文件时剪贴板里往往也带着文件路径文字，那不是用户想粘的内容。
  if (fileCount > 0) return DesktopPasteDecision.attachFiles;

  final decision = decideChatPasteHandling(
    [
      if (hasImage) const ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
      if (plainText.isNotEmpty)
        const ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
    ],
    textEditingFocused: textEditingFocused,
    plainText: plainText,
  );
  return switch (decision) {
    ChatPasteDecision.uploadImage => DesktopPasteDecision.attachImage,
    ChatPasteDecision.letTextPaste => textEditingFocused
        ? DesktopPasteDecision.pasteText
        : DesktopPasteDecision.ignore,
    ChatPasteDecision.uploadHtmlImage ||
    ChatPasteDecision.ignore =>
      DesktopPasteDecision.ignore,
  };
}

/// 按文件头判断图片格式（剪贴板插件只给字节，不给类型）。
String? sniffImageMimeType(List<int> bytes) {
  bool startsWith(List<int> magic, [int offset = 0]) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (startsWith(const [0x42, 0x4D])) return 'image/bmp';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  if (startsWith(const [0x49, 0x49, 0x2A, 0x00]) ||
      startsWith(const [0x4D, 0x4D, 0x00, 0x2A])) {
    return 'image/tiff';
  }
  return null;
}

const _extensionByImageMime = <String, String>{
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/gif': 'gif',
  'image/bmp': 'bmp',
  'image/webp': 'webp',
  'image/tiff': 'tiff',
};

/// 和网页版粘贴图片同样的命名：paste_<毫秒>.<扩展名>。
String pastedImageFileName(String mimeType, {DateTime? now}) {
  final extension = _extensionByImageMime[mimeType] ?? 'png';
  final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return 'paste_$ms.$extension';
}
