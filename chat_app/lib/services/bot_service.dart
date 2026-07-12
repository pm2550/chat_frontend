import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import 'auth_service.dart';
import 'persistent_data_cache.dart';
import 'request_coordinator.dart';

typedef BotAuthenticatedRequest = Future<dynamic> Function(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
});

class BotConfig {
  final int? id;
  final String botName;
  final String? botAvatar;
  final String llmProvider;
  final String? modelName;
  final String? systemPrompt;
  final double temperature;
  final int maxTokens;
  final int maxHistoryMessages;
  final bool includeRoomMetadata;
  final bool visionInputEnabled;
  final bool historyImageInspectionEnabled;
  final String replyMode;
  final String workflowMode;
  final String imageGenerationProvider;
  final int? imageProviderCredentialId;
  final String? imageProviderCredentialLabel;
  final String? imageProviderCredentialLast4;
  final bool hasImageProviderCredential;
  final String? imageModel;
  final String? imageNegativePrompt;
  final bool isActive;
  final String? triggerMode;
  final String? triggerKeywords;
  final String? roomNickname;
  final String? roomPromptSuffix;
  final bool enabledInRoom;

  /// F5: per-room moderation grant for this bot — NONE | MUTE | KICK (owner-set).
  final String? moderationGrant;
  final int? providerCredentialId;
  final String? providerCredentialLabel;
  final String? providerCredentialLast4;
  final bool hasCredential;
  final int? createdById;
  final bool hasCharacterCard;
  final String? characterPersona;
  final String? characterScenario;
  final String? characterFirstMes;
  final List<String> characterAlternateGreetings;
  final int characterBookEntryCount;
  final List<String> enabledTools;
  final String accessPolicy;
  final List<BotAllowedUser> allowedUsers;
  final List<String> allowedUsernames;
  final String? inboundTokenLast4;
  final List<String> inboundTokenScopes;

  BotConfig({
    this.id,
    required this.botName,
    this.botAvatar,
    required this.llmProvider,
    this.modelName,
    this.systemPrompt,
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.maxHistoryMessages = 20,
    this.includeRoomMetadata = true,
    this.visionInputEnabled = true,
    this.historyImageInspectionEnabled = true,
    this.replyMode = 'SINGLE',
    this.workflowMode = 'SINGLE_PASS',
    this.imageGenerationProvider = 'HERMES',
    this.imageProviderCredentialId,
    this.imageProviderCredentialLabel,
    this.imageProviderCredentialLast4,
    this.hasImageProviderCredential = false,
    this.imageModel,
    this.imageNegativePrompt,
    this.isActive = true,
    this.triggerMode,
    this.triggerKeywords,
    this.roomNickname,
    this.roomPromptSuffix,
    this.enabledInRoom = true,
    this.moderationGrant,
    this.providerCredentialId,
    this.providerCredentialLabel,
    this.providerCredentialLast4,
    this.hasCredential = false,
    this.createdById,
    this.hasCharacterCard = false,
    this.characterPersona,
    this.characterScenario,
    this.characterFirstMes,
    this.characterAlternateGreetings = const [],
    this.characterBookEntryCount = 0,
    this.enabledTools = const [],
    this.accessPolicy = 'PRIVATE',
    this.allowedUsers = const [],
    this.allowedUsernames = const [],
    this.inboundTokenLast4,
    this.inboundTokenScopes = const [],
  });

  factory BotConfig.fromJson(Map<String, dynamic> json) {
    return BotConfig(
      id: json['id'],
      botName: json['botName'] ?? '',
      botAvatar: json['botAvatar'],
      llmProvider: json['llmProvider'] ?? 'OPENAI',
      modelName: json['modelName'],
      systemPrompt: json['systemPrompt'],
      temperature: (json['temperature'] ?? 0.7).toDouble(),
      maxTokens: json['maxTokens'] ?? 2048,
      maxHistoryMessages:
          int.tryParse(json['maxHistoryMessages']?.toString() ?? '') ?? 20,
      includeRoomMetadata: json['includeRoomMetadata'] != false,
      visionInputEnabled: json['visionInputEnabled'] != false,
      historyImageInspectionEnabled:
          json['historyImageInspectionEnabled'] != false,
      replyMode: json['replyMode']?.toString() ?? 'SINGLE',
      workflowMode: json['workflowMode']?.toString() ?? 'SINGLE_PASS',
      imageGenerationProvider:
          json['imageGenerationProvider']?.toString() ?? 'HERMES',
      imageProviderCredentialId: json['imageProviderCredentialId'] is int
          ? json['imageProviderCredentialId'] as int
          : int.tryParse(json['imageProviderCredentialId']?.toString() ?? ''),
      imageProviderCredentialLabel:
          json['imageProviderCredentialLabel']?.toString(),
      imageProviderCredentialLast4:
          json['imageProviderCredentialLast4']?.toString(),
      hasImageProviderCredential: json['hasImageProviderCredential'] == true,
      imageModel: json['imageModel']?.toString(),
      imageNegativePrompt: json['imageNegativePrompt']?.toString(),
      isActive: json['isActive'] ?? true,
      triggerMode: json['triggerMode']?.toString(),
      triggerKeywords: json['triggerKeywords']?.toString(),
      roomNickname: json['roomNickname']?.toString(),
      roomPromptSuffix: json['roomPromptSuffix']?.toString(),
      enabledInRoom: json['enabledInRoom'] ?? true,
      moderationGrant: json['moderationGrant']?.toString(),
      providerCredentialId: json['providerCredentialId'] is int
          ? json['providerCredentialId'] as int
          : int.tryParse(json['providerCredentialId']?.toString() ?? ''),
      providerCredentialLabel: json['providerCredentialLabel']?.toString(),
      providerCredentialLast4: json['providerCredentialLast4']?.toString(),
      hasCredential: json['hasCredential'] == true,
      createdById: json['createdById'] is int
          ? json['createdById'] as int
          : int.tryParse(json['createdById']?.toString() ?? ''),
      hasCharacterCard: json['hasCharacterCard'] == true,
      characterPersona: json['characterPersona']?.toString(),
      characterScenario: json['characterScenario']?.toString(),
      characterFirstMes: json['characterFirstMes']?.toString(),
      characterAlternateGreetings:
          (json['characterAlternateGreetings'] as List<dynamic>?)
                  ?.map((item) => item.toString())
                  .toList(growable: false) ??
              const [],
      characterBookEntryCount:
          int.tryParse(json['characterBookEntryCount']?.toString() ?? '') ?? 0,
      enabledTools: (json['enabledTools'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const [],
      accessPolicy: json['accessPolicy']?.toString() ?? 'PRIVATE',
      allowedUsers: (json['allowedUsers'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(BotAllowedUser.fromJson)
              .toList(growable: false) ??
          const [],
      allowedUsernames: (json['allowedUsernames'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const [],
      inboundTokenLast4: json['inboundTokenLast4']?.toString(),
      inboundTokenScopes: (json['inboundTokenScopes'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'botName': botName,
        'botAvatar': botAvatar,
        'llmProvider': llmProvider,
        'modelName': modelName,
        'systemPrompt': systemPrompt,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'maxHistoryMessages': maxHistoryMessages,
        'includeRoomMetadata': includeRoomMetadata,
        'visionInputEnabled': visionInputEnabled,
        'historyImageInspectionEnabled': historyImageInspectionEnabled,
        'replyMode': replyMode,
        'workflowMode': workflowMode,
        'imageGenerationProvider': imageGenerationProvider,
        if (imageProviderCredentialId != null)
          'imageProviderCredentialId': imageProviderCredentialId,
        if (imageModel != null) 'imageModel': imageModel,
        if (imageNegativePrompt != null)
          'imageNegativePrompt': imageNegativePrompt,
        'enabledTools': enabledTools,
        'accessPolicy': accessPolicy,
        'allowedUsernames': allowedUsernames,
        if (providerCredentialId != null)
          'providerCredentialId': providerCredentialId,
      };

  Map<String, dynamic> toCacheJson() => {
        ...toJson(),
        'id': id,
        'isActive': isActive,
        'triggerMode': triggerMode,
        'triggerKeywords': triggerKeywords,
        'roomNickname': roomNickname,
        'roomPromptSuffix': roomPromptSuffix,
        'enabledInRoom': enabledInRoom,
        'moderationGrant': moderationGrant,
        'providerCredentialLabel': providerCredentialLabel,
        'providerCredentialLast4': providerCredentialLast4,
        'imageProviderCredentialLabel': imageProviderCredentialLabel,
        'imageProviderCredentialLast4': imageProviderCredentialLast4,
        'hasImageProviderCredential': hasImageProviderCredential,
        'hasCredential': hasCredential,
        'createdById': createdById,
        'hasCharacterCard': hasCharacterCard,
        'characterPersona': characterPersona,
        'characterScenario': characterScenario,
        'characterFirstMes': characterFirstMes,
        'characterAlternateGreetings': characterAlternateGreetings,
        'characterBookEntryCount': characterBookEntryCount,
        'allowedUsers': allowedUsers.map((user) => user.toJson()).toList(),
        'inboundTokenLast4': inboundTokenLast4,
        'inboundTokenScopes': inboundTokenScopes,
      };

  Map<String, dynamic> toRoomJson() => {
        if (triggerMode != null) 'triggerMode': triggerMode,
        if (triggerKeywords != null) 'triggerKeywords': triggerKeywords,
        if (roomNickname != null) 'roomNickname': roomNickname,
        if (roomPromptSuffix != null) 'roomPromptSuffix': roomPromptSuffix,
        'enabledInRoom': enabledInRoom,
      };
}

class BotAllowedUser {
  const BotAllowedUser({
    required this.id,
    required this.username,
    this.displayName,
  });

  final int id;
  final String username;
  final String? displayName;

  factory BotAllowedUser.fromJson(Map<String, dynamic> json) {
    return BotAllowedUser(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
      };
}

class ProviderCredential {
  const ProviderCredential({
    required this.id,
    required this.llmProvider,
    required this.label,
    this.secretLast4,
    this.isActive = true,
    this.memo,
    this.baseUrl,
    this.modelOverride,
  });

  final int id;
  final String llmProvider;
  final String label;
  final String? secretLast4;
  final bool isActive;
  final String? memo;
  final String? baseUrl;
  final String? modelOverride;

  factory ProviderCredential.fromJson(Map<String, dynamic> json) {
    return ProviderCredential(
      id: json['id'] as int,
      llmProvider: json['llmProvider']?.toString() ?? 'OPENAI',
      label: json['label']?.toString() ?? '',
      secretLast4: json['secretLast4']?.toString(),
      isActive: json['isActive'] != false,
      memo: json['memo']?.toString(),
      // Fields added by Phase 1 backend; fall back to null for older servers.
      baseUrl: json['baseUrl']?.toString(),
      modelOverride: json['modelOverride']?.toString(),
    );
  }
}

class PickedBotAvatar {
  const PickedBotAvatar({
    required this.name,
    this.path,
    this.bytes,
    this.size,
    this.mimeType,
  });

  final String name;
  final String? path;
  final List<int>? bytes;
  final int? size;
  final String? mimeType;
}

class BotServiceException implements Exception {
  const BotServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BotService {
  BotService({
    AuthService? authService,
    BotAuthenticatedRequest? authenticatedRequest,
  })  : _authService = authService ?? AuthService(),
        _authenticatedRequest = authenticatedRequest;

  final AuthService _authService;
  final BotAuthenticatedRequest? _authenticatedRequest;

  Future<BotConfig?> createBot(
    BotConfig config, {
    String? apiKey,
    String? imageApiKey,
    String? imageBaseUrl,
  }) async {
    final body = config.toJson();
    if (apiKey != null && apiKey.isNotEmpty) body['apiKey'] = apiKey;
    if (imageApiKey != null && imageApiKey.isNotEmpty) {
      body['imageApiKey'] = imageApiKey;
    }
    if (imageBaseUrl != null && imageBaseUrl.isNotEmpty) {
      body['imageBaseUrl'] = imageBaseUrl;
    }

    final response = await _request(
      'POST',
      ApiConstants.createBot,
      body: body,
    );

    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return BotConfig.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw const BotServiceException('机器人创建成功但响应中没有数据');
  }

  Future<List<BotConfig>> getMyBots() async {
    if (_authenticatedRequest == null) {
      return RequestCoordinator.run<List<BotConfig>>(
        'bots:${_authService.currentUser?.id ?? 'anonymous'}:mine',
        _loadMyBots,
      );
    }
    return _loadMyBots();
  }

  Future<List<BotConfig>> _loadMyBots() async {
    final response = await _request('GET', ApiConstants.myBots);
    final data = _decodeResponse(response);
    final bots = _extractBots(data);
    final userId = _authService.currentUser?.id;
    if (_authenticatedRequest == null && userId != null) {
      unawaited(PersistentDataCache.write(
        userId: userId,
        namespace: 'bots',
        payload: {
          'bots': bots.map((bot) => bot.toCacheJson()).toList(),
        },
      ));
    }
    return bots;
  }

  Future<List<BotConfig>?> loadPersistedMyBots() async {
    final userId = _authService.currentUser?.id;
    if (_authenticatedRequest != null || userId == null) return null;
    final record = await PersistentDataCache.read(
      userId: userId,
      namespace: 'bots',
    );
    final rawBots = record?['payload']?['bots'];
    if (rawBots is! List<dynamic>) return null;
    return rawBots
        .whereType<Map<String, dynamic>>()
        .map(BotConfig.fromJson)
        .toList(growable: false);
  }

  Future<BotConfig> updateBot(
    int botId,
    BotConfig config, {
    String? apiKey,
    String? imageApiKey,
    String? imageBaseUrl,
  }) async {
    final body = config.toJson();
    if (apiKey != null && apiKey.isNotEmpty) body['apiKey'] = apiKey;
    if (imageApiKey != null && imageApiKey.isNotEmpty) {
      body['imageApiKey'] = imageApiKey;
    }
    if (imageBaseUrl != null && imageBaseUrl.isNotEmpty) {
      body['imageBaseUrl'] = imageBaseUrl;
    }
    final response = await _request(
      'PUT',
      ApiConstants.botDetail(botId),
      body: body,
    );
    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return BotConfig.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw const BotServiceException('机器人更新成功但响应中没有数据');
  }

  Future<BotConfig> uploadBotAvatar(int botId, PickedBotAvatar avatar) async {
    final response = await _requestMultipart(
      ApiConstants.botAvatar(botId),
      avatar: avatar,
    );
    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return BotConfig.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw const BotServiceException('机器人头像上传成功但响应中没有数据');
  }

  Future<bool> addBotToRoom(int roomId, int botId,
      {String? triggerMode,
      String? keywords,
      String? roomNickname,
      String? roomPromptSuffix,
      bool? enabledInRoom}) async {
    final response = await _request(
      'POST',
      ApiConstants.addBotToRoom(roomId, botId),
      body: {
        if (triggerMode != null) 'triggerMode': triggerMode,
        if (keywords != null) 'triggerKeywords': keywords,
        if (roomNickname != null) 'roomNickname': roomNickname,
        if (roomPromptSuffix != null) 'roomPromptSuffix': roomPromptSuffix,
        if (enabledInRoom != null) 'enabledInRoom': enabledInRoom,
      },
    );
    _decodeResponse(response);
    return true;
  }

  Future<BotConfig> updateRoomBotConfig(
    int roomId,
    int botId, {
    String? triggerMode,
    String? keywords,
    String? roomNickname,
    String? roomPromptSuffix,
    bool? enabledInRoom,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.updateRoomBot(roomId, botId),
      body: {
        if (triggerMode != null) 'triggerMode': triggerMode,
        if (keywords != null) 'triggerKeywords': keywords,
        if (roomNickname != null) 'roomNickname': roomNickname,
        if (roomPromptSuffix != null) 'roomPromptSuffix': roomPromptSuffix,
        if (enabledInRoom != null) 'enabledInRoom': enabledInRoom,
      },
    );
    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return BotConfig.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw const BotServiceException('聊天室机器人配置已更新但响应中没有数据');
  }

  Future<bool> removeBotFromRoom(int roomId, int botId) async {
    final response = await _request(
      'DELETE',
      ApiConstants.removeBotFromRoom(roomId, botId),
    );
    _decodeResponse(response);
    return true;
  }

  Future<List<BotConfig>> getBotsInRoom(int roomId) async {
    final response = await _request('GET', ApiConstants.botsInRoom(roomId));
    final data = _decodeResponse(response);
    return _extractBots(data);
  }

  Future<bool> deleteBot(int botId) async {
    final response = await _request('DELETE', ApiConstants.botDetail(botId));
    _decodeResponse(response);
    return true;
  }

  Future<String> rotateInboundToken(int botId) async {
    final response = await _request('POST', ApiConstants.rotateBotToken(botId));
    final data = _decodeResponse(response);
    final token = (data['data'] is Map<String, dynamic>)
        ? (data['data'] as Map<String, dynamic>)['token']?.toString()
        : null;
    if (token == null || token.isEmpty) {
      throw const BotServiceException('令牌已生成但响应中没有 token');
    }
    return token;
  }

  Future<void> revokeInboundToken(int botId) async {
    final response =
        await _request('DELETE', ApiConstants.revokeBotToken(botId));
    _decodeResponse(response);
  }

  Future<List<String>> updateInboundTokenScopes(
    int botId,
    List<String> scopes,
  ) async {
    final response = await _request(
      'PUT',
      ApiConstants.botTokenScopes(botId),
      body: {'scopes': scopes},
    );
    final data = _decodeResponse(response);
    final raw = data['data'] is Map<String, dynamic>
        ? (data['data'] as Map<String, dynamic>)['scopes']
        : null;
    if (raw is List<dynamic>) {
      return raw.map((item) => item.toString()).toList(growable: false);
    }
    return scopes;
  }

  Future<void> registerWebhook(
    int botId, {
    required String callbackUrl,
    String? secret,
    String? eventTypes,
    int? chatRoomId,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.botWebhooks(botId),
      body: {
        'callbackUrl': callbackUrl,
        if (secret != null && secret.isNotEmpty) 'secret': secret,
        if (eventTypes != null && eventTypes.isNotEmpty)
          'eventTypes': eventTypes,
        if (chatRoomId != null) 'chatRoomId': chatRoomId,
      },
    );
    _decodeResponse(response);
  }

  Future<BotConfig> importCharacterCard(
    int botId,
    Map<String, dynamic> card,
  ) async {
    final response = await _request(
      'POST',
      ApiConstants.botCharacterCardImport(botId),
      body: {'card': card},
    );
    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return BotConfig.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw const BotServiceException('角色卡导入成功但响应中没有数据');
  }

  Future<Map<String, dynamic>> exportCharacterCard(int botId) async {
    final response =
        await _request('GET', ApiConstants.botCharacterCardExport(botId));
    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return data['data'] as Map<String, dynamic>;
    }
    throw const BotServiceException('角色卡导出失败');
  }

  Future<List<ProviderCredential>> getProviderCredentials({
    String? provider,
  }) async {
    final url = provider == null || provider.isEmpty
        ? ApiConstants.providerCredentials
        : '${ApiConstants.providerCredentials}?provider=${Uri.encodeQueryComponent(provider)}';
    final response = await _request('GET', url);
    final data = _decodeResponse(response);
    final raw = data['data'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ProviderCredential.fromJson)
          .toList(growable: false);
    }
    return const [];
  }

  Future<ProviderCredential> createProviderCredential({
    required String provider,
    required String label,
    required String secret,
    String? memo,
    String? baseUrl,
    String? modelOverride,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.providerCredentials,
      body: {
        'llmProvider': provider,
        'label': label,
        'secret': secret,
        if (memo != null && memo.isNotEmpty) 'memo': memo,
        if (baseUrl != null && baseUrl.isNotEmpty) 'baseUrl': baseUrl,
        if (modelOverride != null && modelOverride.isNotEmpty)
          'modelOverride': modelOverride,
      },
    );
    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return ProviderCredential.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw const BotServiceException('凭据保存成功但响应中没有数据');
  }

  /// Update an existing credential. Only non-null fields are sent; a blank
  /// [baseUrl]/[modelOverride] clears it server-side.
  Future<ProviderCredential> updateProviderCredential({
    required int credentialId,
    String? label,
    String? secret,
    bool? isActive,
    String? memo,
    String? baseUrl,
    String? modelOverride,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.providerCredentialDetail(credentialId),
      body: {
        if (label != null) 'label': label,
        if (secret != null && secret.isNotEmpty) 'secret': secret,
        if (isActive != null) 'isActive': isActive,
        if (memo != null) 'memo': memo,
        if (baseUrl != null) 'baseUrl': baseUrl,
        if (modelOverride != null) 'modelOverride': modelOverride,
      },
    );
    final data = _decodeResponse(response);
    if (data['data'] is Map<String, dynamic>) {
      return ProviderCredential.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw const BotServiceException('凭据更新成功但响应中没有数据');
  }

  Future<void> deleteProviderCredential(int credentialId) async {
    final response = await _request(
      'DELETE',
      ApiConstants.providerCredentialDetail(credentialId),
    );
    _decodeResponse(response);
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

  Future<dynamic> _requestMultipart(
    String url, {
    required PickedBotAvatar avatar,
  }) async {
    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      final token = _authService.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final bytes = avatar.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        request.files.add(http.MultipartFile.fromBytes(
          'avatar',
          bytes,
          filename: avatar.name,
        ));
      } else if (avatar.path != null && avatar.path!.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath(
          'avatar',
          avatar.path!,
          filename: avatar.name,
        ));
      } else {
        throw const BotServiceException('请选择有效头像');
      }

      final streamedResponse =
          await request.send().timeout(ApiConstants.uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    var response = await send();
    if (response.statusCode == 401 && await _authService.refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  Map<String, dynamic> _decodeResponse(dynamic response) {
    final http.Response typedResponse = response as http.Response;
    if (typedResponse.statusCode < 200 || typedResponse.statusCode >= 300) {
      throw BotServiceException(_extractError(typedResponse.body));
    }
    if (typedResponse.bodyBytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(typedResponse.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is List<dynamic>) {
      return {'data': decoded};
    }
    return {};
  }

  List<BotConfig> _extractBots(Map<String, dynamic> data) {
    final value = data['data'] ?? data['bots'];
    if (value is! List<dynamic>) {
      return [];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(BotConfig.fromJson)
        .toList();
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['message'] ?? decoded['error'] ?? '请求失败').toString();
      }
    } catch (_) {
      // Fall through to generic message.
    }
    return '请求失败';
  }
}
