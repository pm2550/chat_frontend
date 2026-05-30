import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../constants/api_constants.dart';
import '../models/agent_task.dart';
import '../models/chat.dart';
import '../models/chat_room_member.dart';
import '../models/message.dart';
import '../models/poll.dart';
import '../models/read_receipt.dart';
import '../models/sticker.dart';
import '../models/user.dart';
import 'auth_service.dart';

typedef AuthenticatedRequest = Future<dynamic> Function(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
});

typedef AuthenticatedMultipartRequest = Future<dynamic> Function(
  String url, {
  required Map<String, String> fields,
  required PickedChatFile file,
});

typedef AuthenticatedMultipartFilesRequest = Future<dynamic> Function(
  String url, {
  required Map<String, String> fields,
  required Map<String, List<PickedChatFile>> files,
});

class PickedChatFile {
  const PickedChatFile({
    required this.name,
    required this.size,
    this.path,
    this.mimeType,
    this.bytes,
  });

  final String name;
  final int size;
  final String? path;
  final String? mimeType;
  final List<int>? bytes;
}

class DownloadedChatFile {
  const DownloadedChatFile({
    required this.name,
    required this.bytes,
    this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String? mimeType;
}

class MessagePage {
  const MessagePage({
    required this.messages,
    required this.currentPage,
    required this.totalPages,
    required this.totalElements,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<Message> messages;
  final int currentPage;
  final int totalPages;
  final int totalElements;
  final bool hasNext;
  final bool hasPrevious;
}

class ChatDataException implements Exception {
  final String message;

  const ChatDataException(this.message);

  @override
  String toString() => message;
}

class ChatDataService {
  ChatDataService({
    AuthService? authService,
    AuthenticatedRequest? authenticatedRequest,
    AuthenticatedMultipartRequest? multipartRequest,
    AuthenticatedMultipartFilesRequest? multipartFilesRequest,
  })  : _authService = authService ?? AuthService(),
        _authenticatedRequest = authenticatedRequest,
        _multipartRequest = multipartRequest,
        _multipartFilesRequest = multipartFilesRequest;

  final AuthService _authService;
  final AuthenticatedRequest? _authenticatedRequest;
  final AuthenticatedMultipartRequest? _multipartRequest;
  final AuthenticatedMultipartFilesRequest? _multipartFilesRequest;

  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
  }) async {
    final uri = Uri.parse(ApiConstants.chatRooms).replace(
      queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
        'sortBy': 'updatedAt',
        'sortDir': 'desc',
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final rooms =
        _extractList(data, keys: const ['chatRooms', 'data', 'content'])
            .whereType<Map<String, dynamic>>()
            .map(Chat.fromJson)
            .toList();

    if (!includeDetails || rooms.isEmpty) {
      return _sortChats(rooms);
    }

    final visibleRooms = rooms.take(detailLimit).toList(growable: false);
    final remainingRooms = rooms.skip(detailLimit).toList(growable: false);
    final enrichedVisible = await Future.wait(visibleRooms.map(_enrichChat));
    return _sortChats([...enrichedVisible, ...remainingRooms]);
  }

  Future<Chat> getChatRoom(
    String chatRoomId, {
    bool includeDetails = true,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request('GET', ApiConstants.chatRoomDetail(roomId));
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('聊天室详情响应中没有聊天室数据');
    }

    final chat = Chat.fromJson(chatRoomJson);
    return includeDetails ? _enrichChat(chat) : chat;
  }

  Future<Chat> updateChatRoom(
    String chatRoomId, {
    String? name,
    String? description,
    String? avatarUrl,
    String? announcement,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'PATCH',
      ApiConstants.chatRoomDetail(roomId),
      body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (announcement != null) 'announcement': announcement,
      },
    );
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('聊天室更新成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatRoomJson);
  }

  Future<Chat> updateRoomBackgroundPreset(
    String chatRoomId,
    String preset,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'PUT',
      ApiConstants.chatRoomBackgroundPreset(roomId),
      body: {'preset': preset},
    );
    return _chatFromBackgroundResponse(response);
  }

  Future<Chat> uploadRoomBackground(
    String chatRoomId,
    PickedChatFile file,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _requestMultipart(
      ApiConstants.chatRoomBackgroundUpload(roomId),
      fields: const {},
      file: file,
    );
    return _chatFromBackgroundResponse(response);
  }

  Future<Chat> clearRoomBackground(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'DELETE',
      ApiConstants.chatRoomBackground(roomId),
    );
    return _chatFromBackgroundResponse(response);
  }

  Future<Chat> createGroupChat({
    required String name,
    String? description,
    List<String> memberIds = const [],
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.createGroupChat,
      body: {
        'name': name,
        if (description != null) 'description': description,
        'memberIds': memberIds.map(_parseRoomId).toList(),
      },
    );
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('群聊创建成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatRoomJson);
  }

  Future<List<ChatRoomMember>> getChatRoomMembers(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    final response =
        await _request('GET', ApiConstants.chatRoomMembers(roomId));
    final data = _decodeResponse(response);
    return _extractMembers(data);
  }

  Future<List<ChatRoomMember>> addChatRoomMember(
    String chatRoomId,
    String userId,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    final response = await _request(
      'POST',
      ApiConstants.addChatRoomMember(roomId, targetId),
    );
    final data = _decodeResponse(response);
    final members = _extractMembers(data);
    return members.isNotEmpty ? members : getChatRoomMembers(chatRoomId);
  }

  Future<void> leaveChatRoom(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    await _request('POST', ApiConstants.leaveChatRoom(roomId));
  }

  Future<Map<String, dynamic>> getNotificationSettings(
    String chatRoomId,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
        'GET', ApiConstants.chatRoomNotificationSettings(roomId));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> updateNotificationSettings(
    String chatRoomId, {
    bool? muted,
    bool? pinned,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'PUT',
      ApiConstants.chatRoomNotificationSettings(roomId),
      body: {
        if (muted != null) 'muted': muted,
        if (pinned != null) 'pinned': pinned,
      },
    );
    return _decodeResponse(response);
  }

  Future<void> kickChatRoomMember(String chatRoomId, String userId) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    await _request('POST', ApiConstants.kickChatRoomMember(roomId, targetId));
  }

  Future<void> toggleChatRoomAdmin(String chatRoomId, String userId) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    await _request('POST', ApiConstants.toggleChatRoomAdmin(roomId, targetId));
  }

  Future<void> toggleChatRoomMute(String chatRoomId, String userId) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    await _request('POST', ApiConstants.toggleChatRoomMute(roomId, targetId));
  }

  Future<ChatRoomMember> updateChatRoomMemberProfile(
    String chatRoomId,
    String userId, {
    String? nickname,
    String? memberTitle,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    final response = await _request(
      'PUT',
      ApiConstants.chatRoomMemberProfile(roomId, targetId),
      body: {
        if (nickname != null) 'nickname': nickname,
        if (memberTitle != null) 'memberTitle': memberTitle,
      },
    );
    final data = _decodeResponse(response);
    final memberJson = data['member'] ?? data['data'];
    if (memberJson is! Map<String, dynamic>) {
      throw const ChatDataException('群名片更新成功但响应中没有成员数据');
    }
    return ChatRoomMember.fromJson(memberJson);
  }

  Future<List<Message>> getMessages(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    final messagePage =
        await getMessagePage(chatRoomId, page: page, size: size);
    return messagePage.messages;
  }

  Future<MessagePage> getMessagePage(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.chatRoomMessages(roomId)).replace(
      queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return _messagePageFromData(data, messages);
  }

  Future<List<Message>> getRecentMessages(
    String chatRoomId, {
    int limit = 20,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.recentMessages(roomId)).replace(
      queryParameters: {'limit': limit.toString()},
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    return _extractMessages(data, chatRoomId);
  }

  Future<Message> sendTextMessage(
    String chatRoomId,
    String content, {
    bool isAnonymous = false,
    String? replyToId,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.sendMessage,
      body: {
        'chatRoomId': roomId,
        'content': content,
        if (replyToId != null) 'replyToId': _parseRoomId(replyToId),
        if (isAnonymous) 'isAnonymous': true,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<Message> sendTypedMessage(
    String chatRoomId,
    String content, {
    MessageType type = MessageType.text,
    bool isAnonymous = false,
    String? replyToId,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.sendMessage,
      body: {
        'chatRoomId': roomId,
        'content': content,
        'messageType': type.name.toUpperCase(),
        if (replyToId != null) 'replyToId': _parseRoomId(replyToId),
        if (isAnonymous) 'isAnonymous': true,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<Message> sendEncryptedTextMessage(
    String chatRoomId, {
    required String encryptedContent,
    String content = '[加密消息]',
    int encryptionVersion = 1,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.sendMessage,
      body: {
        'chatRoomId': roomId,
        'content': content,
        'messageType': 'TEXT',
        'encryptedContent': encryptedContent,
        'encryptionVersion': encryptionVersion,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有加密消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<Message> sendStickerMessage(
    String chatRoomId,
    int stickerId, {
    bool isAnonymous = false,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.sendMessage,
      body: {
        'chatRoomId': roomId,
        'messageType': 'STICKER',
        'stickerId': stickerId,
        'isAnonymous': isAnonymous,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'] ?? data['message'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有贴纸消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<List<MessageReaction>> addReaction(
    String messageId,
    String emoji,
  ) async {
    final id = _parseRoomId(messageId);
    final response = await _request(
      'POST',
      ApiConstants.messageReactions(id),
      body: {'emoji': emoji},
    );
    return _extractReactions(_decodeResponse(response));
  }

  Future<List<MessageReaction>> removeReaction(
    String messageId,
    String emoji,
  ) async {
    final id = _parseRoomId(messageId);
    final response = await _request(
      'DELETE',
      ApiConstants.messageReaction(id, emoji),
    );
    return _extractReactions(_decodeResponse(response));
  }

  Future<PollInfo> createPoll(
    String chatRoomId, {
    required String question,
    required List<String> options,
    bool multiSelect = false,
    bool anonymous = false,
    DateTime? expiresAt,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.polls,
      body: {
        'chatRoomId': roomId,
        'question': question,
        'options': options,
        'multiSelect': multiSelect,
        'anonymous': anonymous,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      },
    );
    return _pollFromResponse(_decodeResponse(response));
  }

  Future<PollInfo> votePoll(int pollId, List<int> optionIndexes) async {
    final response = await _request(
      'POST',
      ApiConstants.pollVotes(pollId),
      body: {'optionIndexes': optionIndexes},
    );
    return _pollFromResponse(_decodeResponse(response));
  }

  Future<PollInfo> getPoll(int pollId) async {
    final response = await _request('GET', ApiConstants.pollDetail(pollId));
    return _pollFromResponse(_decodeResponse(response));
  }

  Future<List<ReadReceipt>> getReadBy(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('GET', ApiConstants.messageReadBy(id));
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['receipts'] ?? data['readBy'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(ReadReceipt.fromJson)
        .toList();
  }

  Future<List<StickerPack>> getStickerPacks() async {
    final response = await _request('GET', ApiConstants.stickerPacks);
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['packs'] ?? data['stickerPacks'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(StickerPack.fromJson)
        .toList();
  }

  Future<List<StickerItem>> getStickers(int packId) async {
    final response = await _request(
      'GET',
      ApiConstants.stickerPackStickers(packId),
    );
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['stickers'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(StickerItem.fromJson)
        .toList();
  }

  Future<StickerPack> uploadStickerPack({
    required String name,
    required List<PickedChatFile> stickers,
    PickedChatFile? cover,
    bool isPublic = false,
  }) async {
    if (stickers.isEmpty) {
      throw const ChatDataException('至少选择 1 张贴纸图片');
    }
    final response = await _requestMultipartFiles(
      ApiConstants.stickerPacks,
      fields: {
        'name': name.trim().isEmpty ? '我的贴纸包' : name.trim(),
        'isPublic': isPublic.toString(),
      },
      files: {
        if (cover != null) 'cover': [cover],
        'files': stickers,
      },
    );
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['pack'];
    if (value is! Map<String, dynamic>) {
      throw const ChatDataException('贴纸包上传成功但响应无数据');
    }
    return StickerPack.fromJson(value);
  }

  Future<Message> sendFileMessage(
    String chatRoomId,
    PickedChatFile file, {
    MessageType? messageType,
    String? encryptedContent,
    int? encryptionVersion,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final fields = {
      'chatRoomId': roomId.toString(),
      if (messageType != null) 'messageType': messageType.name.toUpperCase(),
      if (encryptedContent != null && encryptedContent.isNotEmpty)
        'encryptedContent': encryptedContent,
      if (encryptionVersion != null)
        'encryptionVersion': encryptionVersion.toString(),
    };
    final response = await _requestMultipart(
      ApiConstants.sendFileMessage,
      fields: fields,
      file: file,
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有文件消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<MessagePage> searchMessages(
    String chatRoomId,
    String keyword, {
    int page = 0,
    int size = 20,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.searchMessagesInRoom(roomId)).replace(
      queryParameters: {
        'q': keyword,
        'offset': (page * size).toString(),
        'limit': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    return _messagePageFromData(data, messages);
  }

  Future<LinkPreview> fetchUrlPreview(String url) async {
    final response = await _request(
      'POST',
      ApiConstants.urlPreview,
      body: {'url': url},
    );
    final data = _decodeResponse(response);
    final previewJson = data['data'] ?? data['preview'];
    if (previewJson is! Map<String, dynamic>) {
      throw const ChatDataException('链接预览响应中没有预览数据');
    }
    return LinkPreview.fromJson(previewJson);
  }

  Future<MessagePage> getMentionedMessages(
    String chatRoomId, {
    int page = 0,
    int size = 20,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.chatRoomMentionsMe(roomId)).replace(
      queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    return _messagePageFromData(data, messages);
  }

  Future<MessagePage> getFileMessages(
    String chatRoomId, {
    MessageType? type,
    int page = 0,
    int size = 50,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.chatRoomFiles(roomId)).replace(
      queryParameters: {
        if (type == MessageType.image || type == MessageType.file)
          'messageType': type!.name.toUpperCase(),
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    return _messagePageFromData(data, messages);
  }

  Future<Message> recallMessage(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('POST', ApiConstants.recallMessage(id));
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已撤回但响应中没有消息数据');
    }
    return Message.fromJson(messageJson);
  }

  Future<Message> deleteMessage(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('DELETE', ApiConstants.deleteMessage(id));
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已删除但响应中没有消息数据');
    }
    return Message.fromJson(messageJson);
  }

  Future<DownloadedChatFile> downloadFile(Message message) async {
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      throw const ChatDataException('消息没有可下载的文件');
    }

    final resolvedUrl = ApiConstants.resolveFileUrl(fileUrl);
    final response = ApiConstants.requiresAuthHeaderForFile(fileUrl)
        ? await _request('GET', resolvedUrl)
        : await http
            .get(Uri.parse(resolvedUrl))
            .timeout(ApiConstants.requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatDataException(_extractError(response.body));
    }

    return DownloadedChatFile(
      name: message.fileName ?? message.content,
      bytes: List<int>.from(response.bodyBytes),
      mimeType: response.headers['content-type'] ?? message.fileType,
    );
  }

  Future<void> markAllRead(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    await _request(
      'POST',
      ApiConstants.markAllRead(roomId),
    );
  }

  Future<void> markMessageRead(String messageId) async {
    final id = _parseRoomId(messageId);
    await _request('POST', ApiConstants.markMessageRead(id));
  }

  Future<void> clearChatHistory(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    await _request('DELETE', ApiConstants.clearChatHistory(roomId));
  }

  Future<int> getUnreadCount(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.unreadCount).replace(
      queryParameters: {'chatRoomId': roomId.toString()},
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final count = data['unreadCount'] ?? data['totalUnreadCount'] ?? 0;
    return count is int ? count : int.tryParse(count.toString()) ?? 0;
  }

  Future<AgentTask> createAgentTask(
    String chatRoomId,
    String prompt, {
    String? botId,
    String? kind,
    String? artifactWorkspaceId,
    String? artifactFolderId,
    String? artifactFileName,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.agentTasks,
      body: {
        'chatRoomId': _parseRoomId(chatRoomId),
        'prompt': prompt,
        if (kind != null && kind.trim().isNotEmpty) 'kind': kind.trim(),
        if (botId != null) 'botId': _parseRoomId(botId),
        if (artifactWorkspaceId != null)
          'artifactWorkspaceId': _parseRoomId(artifactWorkspaceId),
        if (artifactFolderId != null)
          'artifactFolderId': _parseRoomId(artifactFolderId),
        if (artifactFileName != null && artifactFileName.trim().isNotEmpty)
          'artifactFileName': artifactFileName.trim(),
      },
    );
    final data = _decodeResponse(response);
    final taskJson = data['data'];
    if (taskJson is! Map<String, dynamic>) {
      throw const ChatDataException('Agent 任务已创建但响应中没有任务数据');
    }
    return AgentTask.fromJson(taskJson);
  }

  Future<List<AgentTask>> getAgentTasks(
    String chatRoomId, {
    int page = 0,
    int size = 20,
  }) async {
    final uri = Uri.parse(ApiConstants.agentTasks).replace(
      queryParameters: {
        'chatRoomId': _parseRoomId(chatRoomId).toString(),
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final taskContainer = data['data'] is Map<String, dynamic>
        ? data['data'] as Map<String, dynamic>
        : data;
    return _extractList(taskContainer, keys: const ['tasks', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(AgentTask.fromJson)
        .toList();
  }

  Future<Chat> _enrichChat(Chat chat) async {
    Message? lastMessage = chat.lastMessage;
    int unreadCount = chat.unreadCount;
    List<User>? participants;

    try {
      final recent = await getRecentMessages(chat.id, limit: 1);
      if (recent.isNotEmpty) {
        lastMessage = recent.first;
      }
    } catch (_) {
      // Last-message decoration should not block the room list.
    }

    try {
      unreadCount = await getUnreadCount(chat.id);
    } catch (_) {
      // Unread decoration should not block the room list.
    }

    try {
      final members = await getChatRoomMembers(chat.id);
      if (members.isNotEmpty) {
        participants = members.map((member) => member.user).toList();
      }
    } catch (_) {
      // Member decoration should not block the room list.
    }

    bool isPinned = chat.isPinned;
    bool isMuted = chat.isMuted;
    try {
      final settings = await getNotificationSettings(chat.id);
      isPinned = _parseBool(settings['pinned']);
      isMuted = _parseBool(settings['muted']);
    } catch (_) {
      // Per-room preferences are decorative for list loading.
    }

    return chat.copyWith(
      lastMessage: lastMessage,
      unreadCount: unreadCount,
      participants: participants,
      isPinned: isPinned,
      isMuted: isMuted,
    );
  }

  Future<dynamic> _request(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final request = _authenticatedRequest ?? _authService.authenticatedRequest;
    return request(method, url, headers: headers, body: body);
  }

  Chat _chatFromBackgroundResponse(dynamic response) {
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('房间背景更新成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatRoomJson);
  }

  Future<dynamic> _requestMultipart(
    String url, {
    required Map<String, String> fields,
    required PickedChatFile file,
  }) async {
    if (_multipartRequest != null) {
      return _multipartRequest(url, fields: fields, file: file);
    }

    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      final token = _authService.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);

      final bytes = file.bytes;
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
          contentType: _mediaTypeFor(file),
        ));
      } else if (file.path != null && file.path!.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
          contentType: _mediaTypeFor(file),
        ));
      } else {
        throw const ChatDataException('请选择有效文件');
      }

      final streamedResponse =
          await request.send().timeout(ApiConstants.uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    var response = await send();
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        await _authService.refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  Future<dynamic> _requestMultipartFiles(
    String url, {
    required Map<String, String> fields,
    required Map<String, List<PickedChatFile>> files,
  }) async {
    if (_multipartFilesRequest != null) {
      return _multipartFilesRequest(url, fields: fields, files: files);
    }

    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      final token = _authService.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);

      for (final entry in files.entries) {
        for (final file in entry.value) {
          final bytes = file.bytes;
          if (bytes != null) {
            request.files.add(http.MultipartFile.fromBytes(
              entry.key,
              bytes,
              filename: file.name,
              contentType: _mediaTypeFor(file),
            ));
          } else if (file.path != null && file.path!.isNotEmpty) {
            request.files.add(await http.MultipartFile.fromPath(
              entry.key,
              file.path!,
              filename: file.name,
              contentType: _mediaTypeFor(file),
            ));
          } else {
            throw const ChatDataException('请选择有效文件');
          }
        }
      }

      final streamedResponse =
          await request.send().timeout(ApiConstants.uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    var response = await send();
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        await _authService.refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  MediaType? _mediaTypeFor(PickedChatFile file) {
    final mimeType = file.mimeType ?? _mimeTypeFromFileName(file.name);
    if (mimeType == null) return null;
    final parts = mimeType.split('/');
    if (parts.length != 2 || parts.any((part) => part.isEmpty)) return null;
    return MediaType(parts[0], parts[1]);
  }

  String? _mimeTypeFromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    return null;
  }

  List<Chat> _sortChats(List<Chat> chats) {
    chats.sort((a, b) {
      final aTime = a.lastMessage?.timestamp ?? a.updatedAt ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.updatedAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return chats;
  }

  Map<String, dynamic> _decodeResponse(dynamic response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatDataException(_extractHttpError(
        response.statusCode,
        response.body,
      ));
    }
    if (response.bodyBytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is List<dynamic>) {
      return {'data': decoded};
    }
    return {};
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['error'] ?? decoded['message'] ?? '请求失败').toString();
      }
    } catch (_) {
      // Fall through to generic message.
    }
    return '请求失败';
  }

  String _extractHttpError(int statusCode, String body) {
    final error = _extractError(body);
    if (statusCode == 401) {
      return '登录状态已过期，请重新登录';
    }
    if (statusCode == 403) {
      final lower = error.toLowerCase();
      if (lower == 'forbidden' ||
          lower.contains('jwt') ||
          lower.contains('token') ||
          lower.contains('authentication')) {
        return '登录状态已过期，请重新登录';
      }
      return error == '请求失败' ? '没有权限访问此内容' : error;
    }
    return error;
  }

  List<dynamic> _extractList(
    Map<String, dynamic> data, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value is List<dynamic>) {
        return value;
      }
      if (value is Map<String, dynamic>) {
        final nested = _extractList(value, keys: keys);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return const [];
  }

  List<Message> _extractMessages(Map<String, dynamic> data, String chatRoomId) {
    return _extractList(data, keys: const ['messages', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map((json) => Message.fromJson(json, fallbackChatRoomId: chatRoomId))
        .toList();
  }

  List<MessageReaction> _extractReactions(Map<String, dynamic> data) {
    final value = data['data'] ?? data['reactions'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(MessageReaction.fromJson)
        .toList();
  }

  PollInfo _pollFromResponse(Map<String, dynamic> data) {
    final value = data['data'] ?? data['poll'];
    if (value is! Map<String, dynamic>) {
      throw const ChatDataException('投票响应中没有投票数据');
    }
    return PollInfo.fromJson(value);
  }

  MessagePage _messagePageFromData(
    Map<String, dynamic> data,
    List<Message> messages,
  ) {
    final currentPage = _parseInt(data['currentPage']) ?? 0;
    final totalPages = _parseInt(data['totalPages']) ??
        (messages.isEmpty ? 0 : currentPage + 1);
    final totalElements = _parseInt(data['totalElements']) ?? messages.length;
    final hasNext = _parseBool(data['hasNext']) ||
        (totalPages > 0 && currentPage < totalPages - 1);
    final hasPrevious = _parseBool(data['hasPrevious']) || currentPage > 0;

    return MessagePage(
      messages: messages,
      currentPage: currentPage,
      totalPages: totalPages,
      totalElements: totalElements,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  List<ChatRoomMember> _extractMembers(Map<String, dynamic> data) {
    return _extractList(data, keys: const ['members', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(ChatRoomMember.fromJson)
        .toList();
  }

  int _parseRoomId(String chatRoomId) {
    final parsed = int.tryParse(chatRoomId);
    if (parsed == null) {
      throw ChatDataException('无效聊天室ID: $chatRoomId');
    }
    return parsed;
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }
}
