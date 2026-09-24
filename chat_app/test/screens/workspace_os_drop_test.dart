import 'dart:typed_data';

import 'package:chat_app/models/workspace.dart';
import 'package:chat_app/screens/workspace/workspace_page.dart';
import 'package:chat_app/services/os_dropped_files.dart';
import 'package:chat_app/services/workspace_service.dart';
import 'package:chat_app/widgets/os_file_drop_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWorkspaceService extends WorkspaceService {
  _FakeWorkspaceService()
      : super(
          authenticatedRequest: (method, url, {headers, body}) async =>
              throw UnimplementedError(),
        );

  static const workspace = Workspace(
    id: 7,
    name: '项目资料',
    workspaceType: 'TEAM',
    isLocked: false,
    botAccessEnabled: false,
  );

  final uploads = <({int workspaceId, int? folderId, PickedWorkspaceFile file})>[];

  @override
  Future<List<Workspace>> listWorkspaces() async => [workspace];

  @override
  Future<Workspace> getWorkspace(int workspaceId) async => workspace;

  @override
  Future<WorkspaceContents> getContents(int workspaceId, {int? folderId}) async =>
      const WorkspaceContents(folders: [], files: []);

  @override
  Future<WorkspaceFileItem> uploadFile({
    required int workspaceId,
    int? folderId,
    required PickedWorkspaceFile file,
    String? versionNote,
  }) async {
    uploads.add((workspaceId: workspaceId, folderId: folderId, file: file));
    return WorkspaceFileItem.fromJson({
      'id': uploads.length,
      'workspaceId': workspaceId,
      'displayName': file.name,
      'currentVersion': 1,
      'sourceType': 'UPLOAD',
    });
  }
}

void main() {
  testWidgets('files dropped from the OS upload into the open folder',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _FakeWorkspaceService();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WorkspacePage(workspaceService: service)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目资料').first);
    await tester.pumpAndSettle();

    final target = tester.widget<OsFileDropTarget>(
      find.byKey(const Key('workspace-os-drop-target')),
    );
    target.onFilesDropped(DroppedFileBatch(files: [
      DroppedFile(
        name: 'plan.txt',
        size: 3,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      const DroppedFile(name: 'big.mov', size: 99, path: '/tmp/big.mov'),
    ]));
    await tester.pumpAndSettle();

    expect(service.uploads.map((u) => u.file.name), ['plan.txt', 'big.mov']);
    expect(service.uploads.first.workspaceId, 7);
    expect(service.uploads.first.folderId, isNull);
    expect(service.uploads.last.file.path, '/tmp/big.mov');
    expect(find.text('已上传 2 个文件'), findsOneWidget);
  });
}
