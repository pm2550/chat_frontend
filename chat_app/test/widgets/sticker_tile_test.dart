import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/sticker.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/widgets/authenticated_image.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/widgets/sticker_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<circle cx="5" cy="5" r="4" fill="#f5a623"/></svg>';

Future<AuthService> _signedIn(
  Future<http.Response> Function(http.Request request) handler,
) async {
  SharedPreferences.setMockInitialValues({
    'access_token': 'sticker-token',
    'refresh_token': 'sticker-refresh',
    'user_data': jsonEncode({
      'id': 7,
      'username': 'viewer',
      'email': 'viewer@example.com',
      'displayName': 'Viewer',
    }),
  });
  final auth = AuthService.test(httpClient: MockClient(handler));
  await auth.initialize(validateInBackground: false);
  return auth;
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 80, height: 80, child: child)),
      ),
    );

void main() {
  setUp(() {
    AuthenticatedImage.clearCacheForTesting();
    MessageBubble.clearImageCacheForTesting();
  });

  group('StickerTile', () {
    testWidgets('loads protected sticker image with the login token',
        (tester) async {
      final requests = <http.Request>[];
      final auth = await _signedIn((request) async {
        requests.add(request);
        return http.Response.bytes(_png, 200,
            headers: {'content-type': 'image/png'});
      });

      await tester.pumpWidget(_host(StickerTile(
        sticker: const StickerItem(
          id: 1,
          packId: 2,
          url: '/api/files/sticker/abc.png',
          keyword: 'smile',
        ),
        onTap: () {},
        authService: auth,
      )));
      await tester.pump();
      await tester.pump();

      expect(requests, hasLength(1));
      expect(
        requests.single.url.toString(),
        ApiConstants.resolveFileUrl('/api/files/sticker/abc.png'),
      );
      expect(requests.single.headers['Authorization'], 'Bearer sticker-token');
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows a fallback instead of a broken network image on 403',
        (tester) async {
      final auth = await _signedIn(
        (_) async => http.Response('Forbidden', 403),
      );

      await tester.pumpWidget(_host(StickerTile(
        sticker: const StickerItem(
          id: 1,
          packId: 2,
          url: '/api/files/chat/legacy.png',
          keyword: 'wave',
        ),
        onTap: () {},
        authService: auth,
      )));
      await tester.pump();
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.text('wave'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('贴纸加载失败')), findsOneWidget);
    });

    testWidgets('renders system SVG stickers', (tester) async {
      final auth = await _signedIn(
        (_) async => http.Response(_svg, 200,
            headers: {'content-type': 'image/svg+xml'}),
      );

      await tester.pumpWidget(_host(StickerTile(
        sticker: const StickerItem(
          id: 3,
          packId: 1,
          url: '/api/sticker-packs/system-default/happy.svg',
          keyword: 'happy',
        ),
        onTap: () {},
        authService: auth,
      )));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('emoji-only stickers render their keyword and never fetch',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(StickerTile(
        sticker: const StickerItem(id: 4, packId: 1, keyword: '🎉'),
        onTap: () {},
        loader: (_) async {
          calls += 1;
          return _png;
        },
      )));
      await tester.pump();

      expect(find.text('🎉'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('tapping the tile sends the sticker', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(StickerTile(
        sticker: const StickerItem(
          id: 5,
          packId: 1,
          url: '/api/files/sticker/tap.png',
        ),
        onTap: () => taps += 1,
        loader: (_) async => _png,
      )));
      await tester.pump();
      await tester.tap(find.byType(StickerTile));

      expect(taps, 1);
    });
  });

  group('sticker message bubble', () {
    Message stickerMessage(String url) => Message(
          id: '9',
          content: '[贴纸]',
          senderId: 'u2',
          senderName: 'Bob',
          chatRoomId: 'room1',
          type: MessageType.sticker,
          timestamp: DateTime(2026, 9, 24),
          fileUrl: url,
          fileName: 'smile',
          fileType: 'image/sticker',
        );

    testWidgets('does not re-download the sticker on every rebuild',
        (tester) async {
      var loads = 0;
      Future<Uint8List> loader(String _) async {
        loads += 1;
        return _png;
      }

      Widget bubble() => MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: stickerMessage('/api/files/sticker/abc.png'),
                isMe: false,
                imageLoader: loader,
              ),
            ),
          );

      await tester.pumpWidget(bubble());
      await tester.pump();
      await tester.pumpWidget(bubble());
      await tester.pump();
      await tester.pumpWidget(bubble());
      await tester.pump();

      expect(loads, 1);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
