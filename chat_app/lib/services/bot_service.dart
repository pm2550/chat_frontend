import 'dart:convert';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import 'auth_service.dart';

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
  final bool isActive;
  final String? triggerMode;
  final String? triggerKeywords;
  final String? roomNickname;
  final String? roomPromptSuffix;
  final bool enabledInRoom;
  final int? providerCredentialId;
  final String? providerCredentialLabel;
  final String? providerCredentialLast4;
  final bool hasCredential;
  final bool hasCharacterCard;
  final String? characterPersona;
  final String? characterScenario;
  final String? characterFirstMes;
  final List<String> characterAlternateGreetings;
  final int characterBookEntryCount;
  final List<String> enabledTools;

  BotConfig({
    this.id,
    required this.botName,
    this.botAvatar,
    required this.llmProvider,
    this.modelName,
    this.systemPrompt,
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.isActive = true,
    this.triggerMode,
    this.triggerKeywords,
    this.roomNickname,
    this.roomPromptSuffix,
    this.enabledInRoom = true,
    this.providerCredentialId,
    this.providerCredentialLabel,
    this.providerCredentialLast4,
    this.hasCredential = false,
    this.hasCharacterCard = false,
    this.characterPersona,
    this.characterScenario,
    this.characterFirstMes,
    this.characterAlternateGreetings = const [],
    this.characterBookEntryCount = 0,
    this.enabledTools = const [],
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
      isActive: json['isActive'] ?? true,
      triggerMode: json['triggerMode']?.toString(),
      triggerKeywords: json['triggerKeywords']?.toString(),
      roomNickname: json['roomNickname']?.toString(),
      roomPromptSuffix: json['roomPromptSuffix']?.toString(),
      enabledInRoom: json['enabledInRoom'] ?? true,
      providerCredentialId: json['providerCredentialId'] is int
          ? json['providerCredentialId'] as int
          : int.tryParse(json['providerCredentialId']?.toString() ?? ''),
      providerCredentialLabel: json['providerCredentialLabel']?.toString(),
      providerCredentialLast4: json['providerCredentialLast4']?.toString(),
      hasCredential: json['hasCredential'] == true,
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
        'enabledTools': enabledTools,
        if (providerCredentialId != null)
          'providerCredentialId': providerCredentialId,
      };

  Map<String, dynamic> toRoomJson() => {
        if (triggerMode != null) 'triggerMode': triggerMode,
        if (triggerKeywords != null) 'triggerKeywords': triggerKeywords,
        if (roomNickname != null) 'roomNickname': roomNickname,
        if (roomPromptSuffix != null) 'roomPromptSuffix': roomPromptSuffix,
        'enabledInRoom': enabledInRoom,
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

  Future<BotConfig?> createBot(BotConfig config, {String? apiKey}) async {
    final body = config.toJson();
    if (apiKey != null && apiKey.isNotEmpty) body['apiKey'] = apiKey;

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
    final response = await _request('GET', ApiConstants.myBots);
    final data = _decodeResponse(response);
    return _extractBots(data);
  }

  Future<BotConfig> updateBot(int botId, BotConfig config,
      {String? apiKey}) async {
    final body = config.toJson();
    if (apiKey != null && apiKey.isNotEmpty) body['apiKey'] = apiKey;
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
