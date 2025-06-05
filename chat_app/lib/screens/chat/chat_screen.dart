import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../constants/app_colors.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late Chat _chat;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  List<Message> _messages = [];
  bool _isTyping = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chat = ModalRoute.of(context)!.settings.arguments as Chat;
    _initMockMessages();
  }

  void _initMockMessages() {
    final now = DateTime.now();
    final currentUser = User(
      id: 'current',
      username: 'me',
      email: 'me@example.com',
      displayName: '我',
      createdAt: now,
    );

    _messages = [
      Message(
        id: '1',
        content: '你好，今天有空吗？',
        senderId: _chat.participants.first.id,
        senderName: _chat.participants.first.displayName,
        senderAvatar: _chat.participants.first.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.text,
        status: MessageStatus.read,
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
      Message(
        id: '2',
        content: '有空的，什么事？',
        senderId: currentUser.id,
        senderName: currentUser.displayName,
        senderAvatar: currentUser.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: now.subtract(const Duration(hours: 1, minutes: 50)),
      ),
      Message(
        id: '3',
        content: '想约你一起吃饭，你觉得怎么样？',
        senderId: _chat.participants.first.id,
        senderName: _chat.participants.first.displayName,
        senderAvatar: _chat.participants.first.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.text,
        status: MessageStatus.read,
        timestamp: now.subtract(const Duration(hours: 1, minutes: 30)),
      ),
      Message(
        id: '4',
        content: '好啊！什么时候？',
        senderId: currentUser.id,
        senderName: currentUser.displayName,
        senderAvatar: currentUser.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: now.subtract(const Duration(hours: 1, minutes: 20)),
      ),
      Message(
        id: '5',
        content: '晚上7点怎么样？我们在市中心的那家餐厅见面',
        senderId: _chat.participants.first.id,
        senderName: _chat.participants.first.displayName,
        senderAvatar: _chat.participants.first.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.text,
        status: MessageStatus.read,
        timestamp: now.subtract(const Duration(minutes: 30)),
      ),
    ];
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final newMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      senderId: 'current',
      senderName: '我',
      senderAvatar: null,
      chatRoomId: _chat.id,
      type: MessageType.text,
      status: MessageStatus.sending,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(newMessage);
      _messageController.clear();
    });

    _scrollToBottom();

    // 模拟发送状态更新
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == newMessage.id);
          if (index != -1) {
            _messages[index] = newMessage.copyWith(status: MessageStatus.sent);
          }
        });
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == newMessage.id);
          if (index != -1) {
            _messages[index] = newMessage.copyWith(status: MessageStatus.delivered);
          }
        });
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: _chat.avatarUrl != null 
                      ? NetworkImage(_chat.avatarUrl!) 
                      : null,
                  child: _chat.avatarUrl == null
                      ? Text(
                          _chat.type == ChatType.group 
                              ? '群' 
                              : _chat.name.isNotEmpty 
                                  ? _chat.name[0].toUpperCase()
                                  : '?',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                if (_chat.type == ChatType.private && 
                    _chat.participants.isNotEmpty && 
                    _chat.participants.first.onlineStatus == OnlineStatus.online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _chat.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_chat.type == ChatType.private && _chat.participants.isNotEmpty)
                    Text(
                      _chat.participants.first.onlineStatus == OnlineStatus.online
                          ? '在线'
                          : _chat.participants.first.lastSeen != null
                              ? '最后在线 ${timeago.format(_chat.participants.first.lastSeen!, locale: 'zh')}'
                              : '离线',
                      style: TextStyle(
                        fontSize: 12,
                        color: _chat.participants.first.onlineStatus == OnlineStatus.online
                            ? AppColors.online 
                            : AppColors.textSecondary,
                      ),
                    )
                  else if (_chat.type == ChatType.group)
                    Text(
                      '${_chat.participants.length}人',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              // TODO: 实现语音通话
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              // TODO: 实现视频通话
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showChatOptions();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message.senderId == 'current';
                final showTime = index == 0 || 
                    _messages[index - 1].timestamp.difference(message.timestamp).inMinutes.abs() > 5;
                
                return Column(
                  children: [
                    if (showTime)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _formatMessageTime(message.timestamp),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    MessageBubble(
                      message: message,
                      isMe: isMe,
                      showAvatar: !isMe && _chat.type == ChatType.group,
                    ),
                  ],
                );
              },
            ),
          ),

          // 输入栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // 更多选项按钮
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppColors.primary,
                    onPressed: () {
                      _showInputOptions();
                    },
                  ),
                  
                  // 文本输入框
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        maxLines: 4,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: '输入消息...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (text) {
                          setState(() {
                            _isTyping = text.isNotEmpty;
                          });
                        },
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // 发送/语音按钮
                  _isTyping
                      ? IconButton(
                          icon: const Icon(Icons.send),
                          color: AppColors.primary,
                          onPressed: _sendMessage,
                        )
                      : IconButton(
                          icon: const Icon(Icons.mic),
                          color: AppColors.primary,
                          onPressed: () {
                            // TODO: 实现语音消息
                          },
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMessageTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays == 0) {
      return '今天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '${weekdays[timestamp.weekday - 1]} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.month}月${timestamp.day}日 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showInputOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _buildInputOption(
                      icon: Icons.photo_camera,
                      label: '拍照',
                      onTap: () {
                        Navigator.pop(context);
                        // TODO: 实现拍照功能
                      },
                    ),
                    _buildInputOption(
                      icon: Icons.photo_library,
                      label: '相册',
                      onTap: () {
                        Navigator.pop(context);
                        // TODO: 实现选择图片功能
                      },
                    ),
                    _buildInputOption(
                      icon: Icons.attach_file,
                      label: '文件',
                      onTap: () {
                        Navigator.pop(context);
                        // TODO: 实现选择文件功能
                      },
                    ),
                    _buildInputOption(
                      icon: Icons.location_on,
                      label: '位置',
                      onTap: () {
                        Navigator.pop(context);
                        // TODO: 实现发送位置功能
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildChatOption(
                      icon: Icons.search,
                      title: '搜索聊天记录',
                      onTap: () {
                        Navigator.pop(context);
                        // TODO: 实现搜索功能
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.volume_off,
                      title: _chat.isMuted ? '取消静音' : '静音通知',
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _chat = _chat.copyWith(isMuted: !_chat.isMuted);
                        });
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.push_pin,
                      title: _chat.isPinned ? '取消置顶' : '置顶聊天',
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _chat = _chat.copyWith(isPinned: !_chat.isPinned);
                        });
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.delete_outline,
                      title: '删除聊天',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteDialog();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatOption({
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        color: color ?? AppColors.textPrimary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除聊天'),
        content: const Text('确定要删除这个聊天吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              // TODO: 实现删除聊天功能
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
} 