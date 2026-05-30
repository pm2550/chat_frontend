import 'package:chat_app/services/chat_paste_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideChatPasteHandling', () {
    test('lets plain text paste through to the text field', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
      ]);

      expect(decision, ChatPasteDecision.letTextPaste);
    });

    test('uploads image-only clipboard content', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
      ]);

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('lets mixed image and text paste as text when editing', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
        ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
      ], textEditingFocused: true);

      expect(decision, ChatPasteDecision.letTextPaste);
    });

    test('uploads mixed image and text when not editing', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
        ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
      ], textEditingFocused: false);

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('lets html clipboard text paste through when editing', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'image/jpeg'),
        ChatClipboardItemInfo(kind: 'string', type: 'text/html'),
      ], textEditingFocused: true);

      expect(decision, ChatPasteDecision.letTextPaste);
    });

    test('uploads iOS-style image with filename sibling outside editing', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
        ChatClipboardItemInfo(kind: 'string', type: 'text/uri-list'),
      ], textEditingFocused: false);

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('ignores unsupported clipboard content', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'application/pdf'),
      ]);

      expect(decision, ChatPasteDecision.ignore);
    });
  });
}
