import 'chat_data_service.dart';

typedef StickerFilePicker = Future<List<PickedChatFile>> Function({
  required bool allowMultiple,
  required List<String> allowedExtensions,
});
