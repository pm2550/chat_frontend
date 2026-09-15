import 'package:chat_app/services/chat_paste_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideChatPasteHandling', () {
    test('lets plain text paste through to the text field', () {
      final decision = decideChatPasteHandling(
        const [ChatClipboardItemInfo(kind: 'string', type: 'text/plain')],
        plainText: '你好',
      );

      expect(decision, ChatPasteDecision.letTextPaste);
    });

    test('uploads image-only clipboard content', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
      ]);

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('uploads image copied from a web page while composing', () {
      // Chrome「复制图像」：图片文件 + 一个描述图片的 text/html，text/plain 为空。
      final decision = decideChatPasteHandling(
        const [
          ChatClipboardItemInfo(kind: 'string', type: 'text/html'),
          ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
        ],
        textEditingFocused: true,
        htmlText: '<img src="https://example.com/a.png">',
      );

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('uploads image file whose text sibling is just a file name', () {
      final decision = decideChatPasteHandling(
        const [
          ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
          ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
        ],
        textEditingFocused: true,
        plainText: 'IMG_2035.PNG',
      );

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('uploads image file whose text sibling is just the image url', () {
      final decision = decideChatPasteHandling(
        const [
          ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
          ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
        ],
        textEditingFocused: true,
        plainText: 'https://example.com/photo.jpg',
      );

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('lets rich text with real words paste as text while composing', () {
      final decision = decideChatPasteHandling(
        const [
          ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
          ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
        ],
        textEditingFocused: true,
        plainText: '一段文字 文字后缀',
      );

      expect(decision, ChatPasteDecision.letTextPaste);
    });

    test('uploads rich text image when no text field is focused', () {
      final decision = decideChatPasteHandling(
        const [
          ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
          ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
        ],
        textEditingFocused: false,
        plainText: '一段文字 文字后缀',
      );

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('uploads iOS-style image with filename sibling outside editing', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'image/png'),
        ChatClipboardItemInfo(kind: 'string', type: 'text/uri-list'),
      ], textEditingFocused: false);

      expect(decision, ChatPasteDecision.uploadImage);
    });

    test('uploads html-only image selected and copied inside a web page', () {
      // 网页里选中图片 Ctrl+C：剪贴板只有 text/html，没有图片文件。
      final decision = decideChatPasteHandling(
        const [ChatClipboardItemInfo(kind: 'string', type: 'text/html')],
        textEditingFocused: true,
        htmlText:
            '<meta charset="utf-8"><img id="pic" src="https://example.com/a.png" width="64">',
      );

      expect(decision, ChatPasteDecision.uploadHtmlImage);
    });

    test('keeps html with words as a text paste', () {
      final decision = decideChatPasteHandling(
        const [
          ChatClipboardItemInfo(kind: 'string', type: 'text/plain'),
          ChatClipboardItemInfo(kind: 'string', type: 'text/html'),
        ],
        textEditingFocused: true,
        plainText: '一段文字 文字后缀',
        htmlText: '<p>一段文字 <img src="https://example.com/a.png"> 文字后缀</p>',
      );

      expect(decision, ChatPasteDecision.letTextPaste);
    });

    test('ignores unsupported clipboard content', () {
      final decision = decideChatPasteHandling(const [
        ChatClipboardItemInfo(kind: 'file', type: 'application/pdf'),
      ]);

      expect(decision, ChatPasteDecision.ignore);
    });
  });

  group('clipboardTextIsMeaningful', () {
    test('treats empty and image metadata as not meaningful', () {
      expect(clipboardTextIsMeaningful(''), isFalse);
      expect(clipboardTextIsMeaningful('   \n '), isFalse);
      expect(clipboardTextIsMeaningful('screenshot.PNG'), isFalse);
      expect(clipboardTextIsMeaningful('https://example.com/a.webp'), isFalse);
      expect(clipboardTextIsMeaningful('data:image/png;base64,AAAA'), isFalse);
    });

    test('treats real words and links as meaningful', () {
      expect(clipboardTextIsMeaningful('你好'), isTrue);
      expect(clipboardTextIsMeaningful('hello world'), isTrue);
      expect(clipboardTextIsMeaningful('report.pdf'), isTrue);
    });
  });

  group('extractSingleImageSourceFromHtml', () {
    test('returns the src of a lone image', () {
      final src = extractSingleImageSourceFromHtml(
        '<meta charset="utf-8"><!--StartFragment--><img src=\'a.png\' width=64>'
        '<!--EndFragment-->',
      );

      expect(src, 'a.png');
    });

    test('returns null when the html also carries text', () {
      final src = extractSingleImageSourceFromHtml(
        '<p>看这张 <img src="a.png"></p>',
      );

      expect(src, isNull);
    });

    test('returns null for multiple images or no image', () {
      expect(
        extractSingleImageSourceFromHtml('<img src="a.png"><img src="b.png">'),
        isNull,
      );
      expect(extractSingleImageSourceFromHtml('<p></p>'), isNull);
      expect(extractSingleImageSourceFromHtml(''), isNull);
    });
  });
}
