import 'package:chat_app/models/workspace.dart';
import 'package:chat_app/screens/workspace/workspace_text_editor_page.dart';
import 'package:chat_app/services/workspace_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWorkspaceService extends WorkspaceService {
  FakeWorkspaceService({
    this.content = '',
    this.versions = const [],
    this.saveError,
  }) : super(
          authenticatedRequest: (method, url, {headers, body}) async =>
              throw UnimplementedError(),
        );

  String content;
  List<WorkspaceVersion> versions;
  Object? saveError;

  int saveCalls = 0;
  String? lastSavedContent;
  int? restoredVersion;

  @override
  Future<WorkspaceTextContent> readText({
    required int workspaceId,
    required int fileId,
  }) async {
    return WorkspaceTextContent(
      fileId: fileId,
      displayName: 'note.txt',
      currentVersion: 2,
      content: content,
    );
  }

  @override
  Future<WorkspaceFileItem> saveText({
    required int workspaceId,
    required int fileId,
    required String content,
    int? sourceBotId,
    String? versionNote,
  }) async {
    saveCalls++;
    lastSavedContent = content;
    if (saveError != null) throw saveError!;
    return WorkspaceFileItem(
      id: fileId,
      workspaceId: workspaceId,
      displayName: 'note.txt',
      currentVersion: 3,
      sourceType: 'USER',
      isLocked: false,
      botAccessEnabled: false,
    );
  }

  @override
  Future<List<WorkspaceVersion>> listVersions({
    required int workspaceId,
    required int fileId,
  }) async {
    return versions;
  }

  @override
  Future<WorkspaceFileItem> restoreVersion({
    required int workspaceId,
    required int fileId,
    required int versionNumber,
  }) async {
    restoredVersion = versionNumber;
    return WorkspaceFileItem(
      id: fileId,
      workspaceId: workspaceId,
      displayName: 'note.txt',
      currentVersion: 4,
      sourceType: 'USER',
      isLocked: false,
      botAccessEnabled: false,
    );
  }
}

WorkspaceVersion version(int n, {String? note}) => WorkspaceVersion(
      id: n * 10,
      fileId: 5,
      versionNumber: n,
      originalName: 'note.txt',
      versionNote: note,
    );

Widget wrap(FakeWorkspaceService svc) => MaterialApp(
      home: WorkspaceTextEditorPage(
        workspaceId: 1,
        fileId: 5,
        fileName: 'note.txt',
        service: svc,
      ),
    );

void main() {
  group('WorkspaceTextEditorPage', () {
    testWidgets('loads text content from service', (tester) async {
      final svc = FakeWorkspaceService(content: 'hello world');
      await tester.pumpWidget(wrap(svc));
      await tester.pumpAndSettle();

      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets('edit + save calls saveText with the new content',
        (tester) async {
      final svc = FakeWorkspaceService(content: 'old');
      await tester.pumpWidget(wrap(svc));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'new content');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(svc.saveCalls, 1);
      expect(svc.lastSavedContent, 'new content');
    });

    testWidgets('conflict response triggers reload dialog', (tester) async {
      final svc = FakeWorkspaceService(content: 'old')
        ..saveError = const WorkspaceException('conflict', statusCode: 409);
      await tester.pumpWidget(wrap(svc));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('版本冲突'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
    });

    testWidgets('version history lists versions; restore confirm appears',
        (tester) async {
      final svc = FakeWorkspaceService(
        content: 'body',
        versions: [version(2, note: 'second'), version(1, note: 'first')],
      );
      await tester.pumpWidget(wrap(svc));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('历史版本'));
      await tester.pumpAndSettle();

      expect(find.text('版本 1'), findsOneWidget);
      expect(find.text('版本 2'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget); // version 2 == current

      await tester.tap(find.text('恢复')); // only version 1 offers restore
      await tester.pumpAndSettle();

      expect(find.text('恢复版本'), findsOneWidget); // confirm dialog header
    });
  });
}
