enum ChatPasteDecision {
  ignore,
  letTextPaste,
  uploadImage,
  uploadHtmlImage,
}

class ChatClipboardItemInfo {
  const ChatClipboardItemInfo({
    required this.kind,
    required this.type,
  });

  final String kind;
  final String type;
}

/// 决定一次粘贴该发图片还是让文本进输入框。
///
/// [plainText] / [htmlText] 是剪贴板里同名 flavor 的真实内容（paste 事件里可同步取到）。
/// 判定看「剪贴板里有没有图片」+「有没有用户真正想粘的文字」——浏览器复制图片时
/// 几乎总会附带 text/html 或文件名，那些不是文字，不能因此丢掉图片。
ChatPasteDecision decideChatPasteHandling(
  Iterable<ChatClipboardItemInfo> items, {
  bool textEditingFocused = false,
  String plainText = '',
  String htmlText = '',
}) {
  final normalized = items
      .map(
        (item) => ChatClipboardItemInfo(
          kind: item.kind.toLowerCase(),
          type: item.type.toLowerCase(),
        ),
      )
      .toList(growable: false);

  final hasFile = normalized.any((item) => item.kind == 'file');
  final hasTextRepresentation = normalized.any(
    (item) =>
        item.kind == 'string' &&
        (item.type == 'text/plain' || item.type == 'text/html'),
  );
  final hasImageFile = normalized.any(
    (item) => item.kind == 'file' && item.type.startsWith('image/'),
  );
  final meaningfulText = clipboardTextIsMeaningful(plainText);

  if (hasImageFile) {
    // 富文本（文字里夹着图）在输入框里粘贴时仍按文字处理，其余一律发图。
    if (textEditingFocused && meaningfulText) {
      return ChatPasteDecision.letTextPaste;
    }
    return ChatPasteDecision.uploadImage;
  }

  if (hasFile) {
    return hasTextRepresentation && textEditingFocused
        ? ChatPasteDecision.letTextPaste
        : ChatPasteDecision.ignore;
  }

  // 网页里选中一张图直接 Ctrl+C：剪贴板只有 text/html，没有图片文件。
  if (!meaningfulText && extractSingleImageSourceFromHtml(htmlText) != null) {
    return ChatPasteDecision.uploadHtmlImage;
  }

  if (hasTextRepresentation) {
    return ChatPasteDecision.letTextPaste;
  }

  return ChatPasteDecision.ignore;
}

final _whitespacePattern = RegExp(r'\s');
final _imageExtensionPattern =
    RegExp(r'\.(png|jpe?g|gif|webp|bmp|heic|heif|tiff?|avif|svg)$');

/// 剪贴板里的 text/plain 是不是用户真想粘的文字。
///
/// 复制图片时附带的文件名（`IMG_2035.png`）和图片地址（`https://…/a.png`）
/// 都只是图片的元数据，不算文字。
bool clipboardTextIsMeaningful(String plainText) {
  final text = plainText.trim();
  if (text.isEmpty) return false;
  if (_whitespacePattern.hasMatch(text)) return true;

  final lower = text.toLowerCase();
  if (lower.startsWith('data:image/') ||
      lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('file://')) {
    return false;
  }
  return !_imageExtensionPattern.hasMatch(lower);
}

final _imgTagPattern = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _commentPattern = RegExp(r'<!--[\s\S]*?-->');
final _anyTagPattern = RegExp(r'<[^>]*>');
final _entityPattern = RegExp(r'&(nbsp|zwnj|zwj|#8203);?', caseSensitive: false);
final _srcAttributePattern = RegExp(
  '''\\bsrc\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))''',
  caseSensitive: false,
);

/// 当 html 片段只包含一张图片、没有别的可见文字时返回图片地址，否则返回 null。
String? extractSingleImageSourceFromHtml(String htmlText) {
  if (htmlText.trim().isEmpty) return null;

  final imgTags = _imgTagPattern.allMatches(htmlText).toList(growable: false);
  if (imgTags.length != 1) return null;

  final visibleText = htmlText
      .replaceAll(_commentPattern, ' ')
      .replaceAll(_anyTagPattern, ' ')
      .replaceAll(_entityPattern, ' ')
      .trim();
  if (visibleText.isNotEmpty) return null;

  final match = _srcAttributePattern.firstMatch(imgTags.single.group(0)!);
  if (match == null) return null;

  final src = (match.group(1) ?? match.group(2) ?? match.group(3) ?? '').trim();
  return src.isEmpty ? null : src;
}
