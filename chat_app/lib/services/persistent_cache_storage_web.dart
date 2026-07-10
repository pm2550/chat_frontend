import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const String _databaseName = 'pmchat-performance-cache';
const String _storeName = 'snapshots';
Future<web.IDBDatabase>? _databaseFuture;

Future<web.IDBDatabase> _database() {
  return _databaseFuture ??= _openDatabase();
}

Future<web.IDBDatabase> _openDatabase() {
  final completer = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open(_databaseName, 1);
  request.onupgradeneeded = ((web.Event _) {
    final database = request.result as web.IDBDatabase;
    if (!database.objectStoreNames.contains(_storeName)) {
      database.createObjectStore(_storeName);
    }
  }).toJS;
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as web.IDBDatabase);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      StateError(request.error?.message ?? 'IndexedDB open failed'),
    );
  }).toJS;
  return completer.future;
}

Future<JSAny?> _completeRequest(web.IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess =
      ((web.Event _) => completer.complete(request.result)).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      StateError(request.error?.message ?? 'IndexedDB request failed'),
    );
  }).toJS;
  return completer.future;
}

Future<String?> read(String key) async {
  final database = await _database();
  final transaction = database.transaction(_storeName.toJS, 'readonly');
  final result = await _completeRequest(
    transaction.objectStore(_storeName).get(key.toJS),
  );
  return result?.dartify()?.toString();
}

Future<void> write(String key, String value) async {
  final database = await _database();
  final transaction = database.transaction(_storeName.toJS, 'readwrite');
  await _completeRequest(
    transaction.objectStore(_storeName).put(value.toJS, key.toJS),
  );
}

Future<void> deletePrefix(String prefix) async {
  final database = await _database();
  final transaction = database.transaction(_storeName.toJS, 'readwrite');
  final request = transaction.objectStore(_storeName).openCursor();
  final completer = Completer<void>();
  request.onsuccess = ((web.Event _) {
    final result = request.result;
    if (result == null || result.isUndefinedOrNull) {
      if (!completer.isCompleted) completer.complete();
      return;
    }
    final cursor = result as web.IDBCursorWithValue;
    if (cursor.key?.dartify()?.toString().startsWith(prefix) ?? false) {
      cursor.delete();
    }
    cursor.continue_();
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(request.error?.message ?? 'IndexedDB cursor failed'),
      );
    }
  }).toJS;
  await completer.future;
}
