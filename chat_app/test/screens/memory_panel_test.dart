import 'package:chat_app/models/memory_entry.dart';
import 'package:chat_app/screens/chat/sub/memory_panel.dart';
import 'package:chat_app/services/memory_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMemoryService extends MemoryService {
  FakeMemoryService(this.seed)
      : super(
          authenticatedRequest: (method, url, {headers, body}) async =>
              throw UnimplementedError(),
        );

  List<MemoryEntry> seed;
  int createCalls = 0;
  int deleteCalls = 0;
  MemoryVisibility? lastCreateVisibility;
  String? lastCreateTitle;
  String? lastCreateContent;

  @override
  Future<List<MemoryEntry>> listMemories({
    required int roomId,
    String? q,
    bool includeArchived = false,
  }) async =>
      seed;

  @override
  Future<MemoryEntry> createMemory({
    required int roomId,
    required String title,
    required String content,
    String? keywords,
    required MemoryVisibility visibility,
  }) async {
    createCalls++;
    lastCreateTitle = title;
    lastCreateContent = content;
    lastCreateVisibility = visibility;
    return MemoryEntry(
      id: 999,
      chatRoomId: roomId,
      title: title,
      content: content,
      sourceType: MemorySourceType.user,
      visibility: visibility,
      authorUserId: 1,
    );
  }

  @override
  Future<MemoryEntry> updateMemory({
    required int roomId,
    required int memoryId,
    required String title,
    required String content,
    String? keywords,
    required MemoryVisibility visibility,
  }) async =>
      seed.first;

  @override
  Future<void> setPinned({
    required int roomId,
    required int memoryId,
    required bool pinned,
  }) async {}

  @override
  Future<void> setArchived({
    required int roomId,
    required int memoryId,
    required bool archived,
  }) async {}

  @override
  Future<void> deleteMemory({
    required int roomId,
    required int memoryId,
  }) async {
    deleteCalls++;
  }
}

MemoryEntry mem(
  int id, {
  required String title,
  bool pinned = false,
  MemoryVisibility vis = MemoryVisibility.room,
  int? authorUserId,
  DateTime? updated,
}) =>
    MemoryEntry(
      id: id,
      chatRoomId: 1,
      title: title,
      content: 'content $id',
      sourceType: MemorySourceType.user,
      visibility: vis,
      pinned: pinned,
      authorUserId: authorUserId,
      updatedAt: updated,
    );

Widget wrap(MemoryService service, {String? currentUserId = '1'}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: MemoryPanel(
            service: service,
            roomId: 1,
            currentUserId: currentUserId,
          ),
        ),
      ),
    );

void main() {
  group('MemoryPanel', () {
    testWidgets('renders pinned ROOM entries first', (tester) async {
      final svc = FakeMemoryService([
        mem(1, title: 'Normal', updated: DateTime(2026, 1, 2)),
        mem(2, title: 'Pinned', pinned: true, updated: DateTime(2026, 1, 1)),
      ]);
      await tester.pumpWidget(wrap(svc));
      await tester.pumpAndSettle();

      final pinnedY = tester
          .getTopLeft(find.byKey(const ValueKey('memory-card-2')))
          .dy;
      final normalY = tester
          .getTopLeft(find.byKey(const ValueKey('memory-card-1')))
          .dy;
      expect(pinnedY < normalY, isTrue);
    });

    testWidgets('PRIVATE chip shown only on PRIVATE entries', (tester) async {
      final svc = FakeMemoryService([
        mem(1, title: 'Room one'),
        mem(2, title: 'My private', vis: MemoryVisibility.private, authorUserId: 1),
      ]);
      await tester.pumpWidget(wrap(svc, currentUserId: '1'));
      await tester.pumpAndSettle();

      // Exactly one '私有' chip — on the private card (dialog is closed).
      expect(find.text('私有'), findsOneWidget);
    });

    testWidgets('PRIVATE entry authored by another user is never rendered',
        (tester) async {
      final svc = FakeMemoryService([
        mem(1, title: 'Room one'),
        mem(2, title: 'Their private', vis: MemoryVisibility.private, authorUserId: 2),
      ]);
      await tester.pumpWidget(wrap(svc, currentUserId: '1'));
      await tester.pumpAndSettle();

      // Defence-in-depth: a PRIVATE entry whose author != current user must be dropped.
      expect(find.text('Their private'), findsNothing);
      expect(find.byKey(const ValueKey('memory-card-2')), findsNothing);
      // Sanity: the ROOM entry still renders.
      expect(find.text('Room one'), findsOneWidget);
    });

    testWidgets('add dialog opens, scope toggle works, Save calls createMemory',
        (tester) async {
      final svc = FakeMemoryService([]);
      await tester.pumpWidget(wrap(svc, currentUserId: '1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      expect(find.text('添加记忆'), findsOneWidget);

      await tester.tap(find.text('私有'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '标题'), 'Hello');
      await tester.enterText(find.widgetWithText(TextField, '内容'), 'World');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(svc.createCalls, 1);
      expect(svc.lastCreateVisibility, MemoryVisibility.private);
      expect(svc.lastCreateTitle, 'Hello');
      expect(svc.lastCreateContent, 'World');
    });

    testWidgets('edit hidden on entries authored by someone else',
        (tester) async {
      final svc = FakeMemoryService([
        mem(1, title: 'Theirs', authorUserId: 2),
      ]);
      await tester.pumpWidget(wrap(svc, currentUserId: '1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('memory-menu-1')));
      await tester.pumpAndSettle();

      expect(find.text('编辑'), findsNothing);
      expect(find.text('删除'), findsNothing);
      expect(find.text('置顶'), findsOneWidget);
    });

    testWidgets('delete confirm dialog shows; cancel does not call deleteMemory',
        (tester) async {
      final svc = FakeMemoryService([
        mem(1, title: 'Mine', authorUserId: 1),
      ]);
      await tester.pumpWidget(wrap(svc, currentUserId: '1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('memory-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('删除记忆'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(svc.deleteCalls, 0);
    });
  });
}
