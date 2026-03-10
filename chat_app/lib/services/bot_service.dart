import 'dart:convert';
import '../constants/api_constants.dart';
import 'auth_service.dart';

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

class BotService {
  final AuthService _authService = AuthService();

  Future<BotConfig?> createBot(BotConfig config, {String? apiKey}) async {
    try {
      final body = config.toJson();
      if (apiKey != null) body['apiKey'] = apiKey;

      final response = await _authService.authenticatedRequest(
        'POST', ApiConstants.createBot, body: body,
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] != null) {
        return BotConfig.fromJson(data['data']);
      }
    } catch (e) {
      print('Create bot error: $e');
    }
    return null;
  }

  Future<List<BotConfig>> getMyBots() async {
    try {
      final response = await _authService.authenticatedRequest(
        'GET', ApiConstants.myBots,
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] != null) {
        return (data['data'] as List)
            .map((b) => BotConfig.fromJson(b))
            .toList();
      }
    } catch (e) {
      print('Get bots error: $e');
    }
    return [];
  }

  Future<bool> addBotToRoom(int roomId, int botId, {String? triggerMode, String? keywords}) async {
    try {
      final response = await _authService.authenticatedRequest(
        'POST',
        ApiConstants.addBotToRoom(roomId, botId),
        body: {
          if (triggerMode != null) 'triggerMode': triggerMode,
          if (keywords != null) 'triggerKeywords': keywords,
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Add bot to room error: $e');
      return false;
    }
  }

  Future<bool> removeBotFromRoom(int roomId, int botId) async {
    try {
      final response = await _authService.authenticatedRequest(
        'DELETE', ApiConstants.removeBotFromRoom(roomId, botId),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<BotConfig>> getBotsInRoom(int roomId) async {
    try {
      final response = await _authService.authenticatedRequest(
        'GET', ApiConstants.botsInRoom(roomId),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] != null) {
        return (data['data'] as List)
            .map((b) => BotConfig.fromJson(b))
            .toList();
      }
    } catch (e) {
      print('Get room bots error: $e');
    }
    return [];
  }

  Future<bool> deleteBot(int botId) async {
    try {
      final response = await _authService.authenticatedRequest(
        'DELETE', ApiConstants.botDetail(botId),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
