import 'dart:convert';

import 'package:chat_app/services/workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('WorkspaceService', () {
    test('listWorkspaces parses quota and access metadata', () async {
      final service = WorkspaceService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(Uri.parse(url).path, '/api/v1/workspaces');
          return jsonResponse({
            'data': [
              {
                'id': 7,
                'name': 'Team vault',
                'workspaceType': 'TEAM',
                'myAccessLevel': 'MANAGE',
                'isLocked': false,
                'botAccessEnabled': true,
                'quotaBytes': 1024,
                'usedBytes': 256,
              },
            ],
          });
        },
      );

      final workspaces = await service.listWorkspaces();

      expect(workspaces.single.name, 'Team vault');
      expect(workspaces.single.quotaBytes, 1024);
      expect(workspaces.single.usedBytes, 256);
      expect(workspaces.single.myAccessLevel, 'MANAGE');
    });

    test('member and permission calls use workspace endpoints', () async {
      final calls = <String>[];
      Object? memberBody;
      Object? permissionBody;
      final service = WorkspaceService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method ${Uri.parse(url).path}');
          if (url.endsWith('/members') && method == 'GET') {
            return jsonResponse({
              'data': [
                {
                  'id': 1,
                  'userId': 9,
                  'username': 'alice',
                  'displayName': 'Alice',
                  'role': 'EDITOR',
                },
              ],
            });
          }
          if (url.endsWith('/members') && method == 'POST') {
            memberBody = body;
            return jsonResponse({
              'data': {
                'id': 2,
                'userId': 10,
                'username': 'bob',
                'displayName': 'Bob',
                'role': 'VIEWER',
              },
            });
          }
          if (url.endsWith('/permissions') && method == 'GET') {
            return jsonResponse({
              'data': [
                {
                  'id': 3,
                  'workspaceId': 7,
                  'resourceType': 'FILE',
                  'resourceId': 11,
                  'resourceName': 'roadmap.txt',
                  'principalType': 'USER',
                  'principalId': 10,
                  'principalName': 'Bob',
                  'accessLevel': 'EDIT',
                },
              ],
            });
          }
          if (url.endsWith('/permissions/3') && method == 'DELETE') {
            return jsonResponse({'data': null});
          }
          permissionBody = body;
          return jsonResponse({
            'data': {
              'id': 3,
              'workspaceId': 7,
              'resourceType': 'FILE',
              'resourceId': 11,
              'principalType': 'USER',
              'principalId': 10,
              'accessLevel': 'EDIT',
            }
          });
        },
      );

      final members = await service.listMembers(7);
      final added = await service.addMember(
        workspaceId: 7,
        userId: 10,
        role: 'VIEWER',
      );
      final permissions = await service.listPermissions(7);
      final permission = await service.grantPermission(
        workspaceId: 7,
        resourceType: 'FILE',
        resourceId: 11,
        principalType: 'USER',
        principalId: 10,
        accessLevel: 'EDIT',
      );
      await service.revokePermission(workspaceId: 7, permissionId: 3);

      expect(members.single.username, 'alice');
      expect(added.displayName, 'Bob');
      expect(permissions.single.principalName, 'Bob');
      expect(permission.accessLevel, 'EDIT');
      expect(memberBody, {'userId': 10, 'role': 'VIEWER'});
      expect(permissionBody, {
        'resourceType': 'FILE',
        'resourceId': 11,
        'principalType': 'USER',
        'principalId': 10,
        'accessLevel': 'EDIT',
      });
      expect(calls, [
        'GET /api/v1/workspaces/7/members',
        'POST /api/v1/workspaces/7/members',
        'GET /api/v1/workspaces/7/permissions',
        'POST /api/v1/workspaces/7/permissions',
        'DELETE /api/v1/workspaces/7/permissions/3',
      ]);
    });

    test('trash, restore version and maintenance parse backend responses',
        () async {
      final calls = <String>[];
      final service = WorkspaceService(
        authenticatedRequest: (method, url, {headers, body}) async {
          final uri = Uri.parse(url);
          calls.add('$method ${uri.path}?${uri.query}');
          if (uri.path.endsWith('/trash')) {
            return jsonResponse({
              'data': {
                'folders': [
                  {
                    'id': 4,
                    'workspaceId': 7,
                    'name': 'Old',
                    'isLocked': false,
                    'botAccessEnabled': false,
                    'isDeleted': true,
                  },
                ],
                'files': [
                  {
                    'id': 5,
                    'workspaceId': 7,
                    'displayName': 'old.txt',
                    'currentVersion': 1,
                    'sourceType': 'USER',
                    'isLocked': false,
                    'botAccessEnabled': false,
                    'isDeleted': true,
                    'scanStatus': 'CLEAN',
                  },
                ],
              },
            });
          }
          if (uri.path.contains('/versions/1/restore')) {
            return jsonResponse({
              'data': {
                'id': 5,
                'workspaceId': 7,
                'displayName': 'old.txt',
                'currentVersion': 3,
                'sourceType': 'USER',
                'isLocked': false,
                'botAccessEnabled': false,
                'scanStatus': 'CLEAN',
              },
            });
          }
          return jsonResponse({
            'data': {
              'orphanCount': 2,
              'deletedCount': 0,
              'bytes': 12,
              'dryRun': true,
              'fileNames': ['a.bin', 'b.bin'],
            },
          });
        },
      );

      final trash = await service.listTrash(7);
      final restored = await service.restoreVersion(
        workspaceId: 7,
        fileId: 5,
        versionNumber: 1,
      );
      final maintenance = await service.cleanupOrphans(7);

      expect(trash.folders.single.name, 'Old');
      expect(trash.files.single.scanStatus, 'CLEAN');
      expect(restored.currentVersion, 3);
      expect(maintenance.orphanCount, 2);
      expect(maintenance.fileNames, ['a.bin', 'b.bin']);
      expect(calls, [
        'GET /api/v1/workspaces/7/trash?',
        'POST /api/v1/workspaces/7/files/5/versions/1/restore?',
        'POST /api/v1/workspaces/7/maintenance/orphans?dryRun=true',
      ]);
    });
  });
}

http.Response jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
