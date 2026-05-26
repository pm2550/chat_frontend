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
      };
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
      {String? triggerMode, String? keywords}) async {
    final response = await _request(
      'POST',
      ApiConstants.addBotToRoom(roomId, botId),
      body: {
        if (triggerMode != null) 'triggerMode': triggerMode,
        if (keywords != null) 'triggerKeywords': keywords,
      },
    );
    _decodeResponse(response);
    return true;
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
