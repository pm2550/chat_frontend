import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/design.dart';
import '../models/message.dart';

abstract class AgentClientTool {
  String get name;
  Future<Map<String, dynamic>> execute(Map<String, dynamic> params);
}

typedef AgentConfirmationPresenter = Future<String> Function(
  String question,
  String yesLabel,
  String noLabel,
);

typedef AgentClipboardReader = Future<ClipboardData?> Function(String format);

class AgentClientToolRegistry {
  static final AgentClientToolRegistry _instance =
      AgentClientToolRegistry._internal();

  factory AgentClientToolRegistry() => _instance;

  AgentClientToolRegistry._internal();

  final Map<String, AgentClientTool> _byName = {};

  void register(AgentClientTool tool) {
    _byName[tool.name] = tool;
  }

  AgentClientTool? getByName(String name) => _byName[name];

  void registerDefaults({AgentClientToolState? state}) {
    final runtime = state ?? AgentClientToolState();
    register(GetLocalRoomSettingsTool(runtime));
    register(GetOpenChatPanelsTool(runtime));
    register(GetRecentAttachmentsTool(runtime));
    register(PromptUserConfirmationTool(runtime));
    register(ReadClipboardTool(runtime));
  }

  @visibleForTesting
  void clearForTesting() {
    _byName.clear();
  }
}

class AgentClientToolState {
  static final AgentClientToolState _instance =
      AgentClientToolState._internal();

  factory AgentClientToolState() => _instance;

  AgentClientToolState._internal();

  final Map<String, List<Message>> _messagesByRoomId = {};

  GlobalKey<NavigatorState>? navigatorKey;
  AgentConfirmationPresenter? confirmationPresenter;
  AgentClipboardReader clipboardReader = Clipboard.getData;

  int? currentRoomId;
  bool muted = false;
  bool pinnedToTop = false;
  String notificationLevel = 'all';
  String? customNickname;
  bool rightSidebarOpen = false;
  String? rightSidebarTab;
  bool membersPanelOpen = false;
  bool settingsOpen = false;

  void updateRoom({
    required int? roomId,
    required bool muted,
    required bool pinnedToTop,
    String? notificationLevel,
    String? customNickname,
    List<Message>? messages,
    bool? rightSidebarOpen,
    String? rightSidebarTab,
    bool? membersPanelOpen,
    bool? settingsOpen,
  }) {
    currentRoomId = roomId;
    this.muted = muted;
    this.pinnedToTop = pinnedToTop;
    this.notificationLevel =
        notificationLevel ?? (muted ? 'none' : this.notificationLevel);
    this.customNickname = customNickname;
    if (roomId != null && messages != null) {
      _messagesByRoomId[roomId.toString()] = List<Message>.from(messages);
    }
    if (rightSidebarOpen != null) this.rightSidebarOpen = rightSidebarOpen;
    if (rightSidebarTab != null) this.rightSidebarTab = rightSidebarTab;
    if (membersPanelOpen != null) this.membersPanelOpen = membersPanelOpen;
    if (settingsOpen != null) this.settingsOpen = settingsOpen;
  }

  List<Message> recentAttachments(String roomId, int n) {
    final messages = List<Message>.from(_messagesByRoomId[roomId] ?? const [])
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages
        .where((message) => message.fileUrl?.trim().isNotEmpty == true)
        .take(n.clamp(0, 20))
        .toList();
  }

  @visibleForTesting
  void resetForTesting() {
    _messagesByRoomId.clear();
    navigatorKey = null;
    confirmationPresenter = null;
    clipboardReader = Clipboard.getData;
    currentRoomId = null;
    muted = false;
    pinnedToTop = false;
    notificationLevel = 'all';
    customNickname = null;
    rightSidebarOpen = false;
    rightSidebarTab = null;
    membersPanelOpen = false;
    settingsOpen = false;
  }
}

class GetLocalRoomSettingsTool implements AgentClientTool {
  const GetLocalRoomSettingsTool(this.state);

  final AgentClientToolState state;

  @override
  String get name => 'get_local_room_settings';

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> params) async {
    return {
      'muted': state.muted,
      'pinnedToTop': state.pinnedToTop,
      'notificationLevel': state.notificationLevel,
      'customNickname': state.customNickname,
    };
  }
}

class GetOpenChatPanelsTool implements AgentClientTool {
  const GetOpenChatPanelsTool(this.state);

  final AgentClientToolState state;

  @override
  String get name => 'get_open_chat_panels';

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> params) async {
    return {
      'currentRoomId': state.currentRoomId,
      'rightSidebarOpen': state.rightSidebarOpen,
      'rightSidebarTab': state.rightSidebarTab,
      'membersPanelOpen': state.membersPanelOpen,
      'settingsOpen': state.settingsOpen,
    };
  }
}

class GetRecentAttachmentsTool implements AgentClientTool {
  const GetRecentAttachmentsTool(this.state);

  final AgentClientToolState state;

  @override
  String get name => 'get_recent_attachments';

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> params) async {
    final roomId =
        (params['roomId'] ?? params['room_id'] ?? state.currentRoomId)
            ?.toString();
    final n = (params['n'] is num ? (params['n'] as num).toInt() : 20)
        .clamp(0, 20)
        .toInt();
    if (roomId == null || roomId.isEmpty) {
      return {'attachments': <Map<String, dynamic>>[]};
    }
    final attachments = state.recentAttachments(roomId, n).map((message) {
      return {
        'messageId': int.tryParse(message.id) ?? message.id,
        'url': message.fileUrl,
        'filename': message.fileName ?? message.content,
        'mimeType': message.fileType,
        'timestamp': message.timestamp.toIso8601String(),
      };
    }).toList();
    return {'attachments': attachments};
  }
}

class PromptUserConfirmationTool implements AgentClientTool {
  const PromptUserConfirmationTool(this.state);

  final AgentClientToolState state;

  @override
  String get name => 'prompt_user_confirmation';

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> params) async {
    final question = params['question']?.toString().trim();
    final yesLabel = params['yes_label']?.toString().trim().isNotEmpty == true
        ? params['yes_label'].toString()
        : '确认';
    final noLabel = params['no_label']?.toString().trim().isNotEmpty == true
        ? params['no_label'].toString()
        : '取消';
    if (question == null || question.isEmpty) {
      return {
        'answered': 'dismissed',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
    final presenter = state.confirmationPresenter ?? _showConfirmationDialog;
    final answered = await presenter(question, yesLabel, noLabel);
    return {
      'answered': answered,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Future<String> _showConfirmationDialog(
    String question,
    String yesLabel,
    String noLabel,
  ) async {
    final context = state.navigatorKey?.currentContext;
    if (context == null) {
      return 'dismissed';
    }
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: PMCard(
              elevated: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PMDialogHeader(
                    title: 'Agent 请求确认',
                    subtitle: question,
                    showHandle: false,
                    onClose: () => Navigator.of(dialogContext).pop('dismissed'),
                  ),
                  const SizedBox(height: PMSpacing.l),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PMButton(
                        label: noLabel,
                        variant: PMButtonVariant.secondary,
                        onPressed: () => Navigator.of(dialogContext).pop('no'),
                      ),
                      const SizedBox(width: PMSpacing.s),
                      PMButton(
                        label: yesLabel,
                        icon: Icons.check,
                        onPressed: () => Navigator.of(dialogContext).pop('yes'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return answer ?? 'dismissed';
  }
}

class ReadClipboardTool implements AgentClientTool {
  const ReadClipboardTool(this.state);

  final AgentClientToolState state;

  @override
  String get name => 'read_clipboard';

  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> params) async {
    try {
      final data = await state.clipboardReader(Clipboard.kTextPlain);
      return {'text': data?.text ?? ''};
    } on PlatformException catch (e) {
      return {
        'error': {
          'code': 'permission_denied',
          'message': e.message ?? 'clipboard permission denied',
        },
      };
    } catch (e) {
      return {
        'error': {
          'code': 'clipboard_error',
          'message': e.toString(),
        },
      };
    }
  }
}
