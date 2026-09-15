import 'chat_data_service.dart';

typedef ChatDragStateChanged = void Function(int fileCount);
typedef ChatFilesDropped = Future<void> Function(List<PickedChatFile> files);
typedef ChatPasteImage = Future<void> Function(PickedChatFile file);
typedef ChatPasteImageUrl = Future<void> Function(String url);

class ChatDropPasteController {
  const ChatDropPasteController();

  void dispose() {}
}

ChatDropPasteController attachChatDropPasteHandlers({
  required ChatDragStateChanged onDragEntered,
  required VoidCallbackLike onDragExited,
  required ChatFilesDropped onFilesDropped,
  required ChatPasteImage onPasteImage,
  required ChatPasteImageUrl onPasteImageUrl,
}) {
  return const ChatDropPasteController();
}

typedef VoidCallbackLike = void Function();
