import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../constants/app_colors.dart';
import '../../models/chat.dart';
import '../../models/user.dart';
import '../../models/message.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 模拟聊天数据
  late List<Chat> _chats;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('zh', timeago.ZhMessages());
    _initMockData();
  }

  void _initMockData() {
    final now = DateTime.now();
    
    final users = [
      User(
        id: '1',
        username: 'zhangsan',
        email: 'zhangsan@example.com',
        displayName: '张三',
        avatarUrl: null,
        onlineStatus: OnlineStatus.online,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now,
      ),
      User(
        id: '2',
        username: 'lisi',
        email: 'lisi@example.com',
        displayName: '李四',
        avatarUrl: null,
        onlineStatus: OnlineStatus.offline,
        lastSeen: now.subtract(const Duration(minutes: 30)),
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now,
      ),
      User(
        id: '3',
        username: 'group',
        email: 'group@example.com',
        displayName: '产品讨论组',
        avatarUrl: null,
        onlineStatus: OnlineStatus.online,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now,
      ),
    ];

    _chats = [
      Chat(
        id: '1',
        name: '张三',
        type: ChatType.private,
        participants: [users[0]],
        lastMessage: Message(
          id: '1',
          content: '你好，今天有空吗？',
          senderId: users[0].id,
          senderName: users[0].displayName,
          senderAvatar: users[0].avatarUrl,
          chatRoomId: '1',
          type: MessageType.text,
          status: MessageStatus.delivered,
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
        unreadCount: 2,
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(minutes: 5)),
      ),
      Chat(
        id: '2',
        name: '李四',
        type: ChatType.private,
        participants: [users[1]],
        lastMessage: Message(
          id: '2',
          content: '收到，谢谢！',
          senderId: users[1].id,
          senderName: users[1].displayName,
          senderAvatar: users[1].avatarUrl,
          chatRoomId: '2',
          type: MessageType.text,
          status: MessageStatus.read,
          timestamp: now.subtract(const Duration(hours: 2)),
        ),
        unreadCount: 0,
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      Chat(
        id: '3',
        name: '产品讨论组',
        type: ChatType.group,
        participants: [users[0], users[1], users[2]],
        lastMessage: Message(
          id: '3',
          content: '明天的会议改到下午3点',
          senderId: users[2].id,
          senderName: users[2].displayName,
          senderAvatar: users[2].avatarUrl,
          chatRoomId: '3',
          type: MessageType.text,
          status: MessageStatus.delivered,
          timestamp: now.subtract(const Duration(hours: 1)),
        ),
        unreadCount: 1,
        isPinned: true,
        createdAt: now.subtract(const Duration(days: 15)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
    ];
  }

  List<Chat> get _filteredChats {
    if (_searchQuery.isEmpty) {
      return _chats;
    }
    return _chats.where((chat) {
      return chat.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (chat.lastMessage?.content.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('聊天'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: 实现搜索功能
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: 实现更多功能
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: '搜索聊天记录',
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
            ),
          ),
          
          // 聊天列表
          Expanded(
            child: _filteredChats.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _filteredChats.length,
                    itemBuilder: (context, index) {
                      final chat = _filteredChats[index];
                      return _buildChatItem(chat);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: AppColors.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? '暂无聊天记录' : '没有找到相关聊天',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮开始新的聊天',
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatItem(Chat chat) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/chat',
            arguments: chat,
          );
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: chat.avatarUrl != null 
                  ? NetworkImage(chat.avatarUrl!) 
                  : null,
              child: chat.avatarUrl == null
                  ? Text(
                      chat.type == ChatType.group 
                          ? '群' 
                          : chat.name.isNotEmpty 
                              ? chat.name[0].toUpperCase()
                              : '?',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            if (chat.type == ChatType.private && 
                chat.participants.isNotEmpty && 
                chat.participants.first.onlineStatus == OnlineStatus.online)
              Positioned(
                right: 2,
                bottom: 2,
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
            if (chat.isPinned)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.push_pin,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                chat.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (chat.lastMessage != null)
              Text(
                timeago.format(chat.lastMessage!.timestamp, locale: 'zh'),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                chat.lastMessage?.content ?? '暂无消息',
                style: TextStyle(
                  color: chat.unreadCount > 0 
                      ? AppColors.textPrimary 
                      : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: chat.unreadCount > 0 
                      ? FontWeight.w500 
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (chat.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: chat.isMuted
            ? const Icon(
                Icons.volume_off,
                size: 16,
                color: AppColors.textSecondary,
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
} 