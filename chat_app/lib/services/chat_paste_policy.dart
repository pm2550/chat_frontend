enum ChatPasteDecision {
  ignore,
  letTextPaste,
  uploadImage,
}

class ChatClipboardItemInfo {
  const ChatClipboardItemInfo({
    required this.kind,
    required this.type,
  });

  final String kind;
  final String type;
}

ChatPasteDecision decideChatPasteHandling(
  Iterable<ChatClipboardItemInfo> items, {
  bool textEditingFocused = false,
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
  final hasStringSibling = normalized.any((item) => item.kind == 'string');
  final hasTextRepresentation = normalized.any(
    (item) =>
        item.kind == 'string' &&
        (item.type == 'text/plain' || item.type == 'text/html'),
  );
  final hasImageFile = normalized.any(
    (item) => item.kind == 'file' && item.type.startsWith('image/'),
  );

  if (!hasFile && hasTextRepresentation) {
    return ChatPasteDecision.letTextPaste;
  }

  if (hasImageFile && hasStringSibling) {
    return textEditingFocused
        ? ChatPasteDecision.letTextPaste
        : ChatPasteDecision.uploadImage;
  }

  if (hasImageFile) {
    return ChatPasteDecision.uploadImage;
  }

  if (hasFile && hasTextRepresentation && textEditingFocused) {
    return ChatPasteDecision.letTextPaste;
  }

  return ChatPasteDecision.ignore;
}
