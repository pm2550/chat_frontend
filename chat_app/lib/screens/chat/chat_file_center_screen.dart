import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/message.dart';
import '../../services/chat_data_service.dart';

class ChatFileCenterScreen extends StatefulWidget {
  const ChatFileCenterScreen({
    super.key,
    required this.chatRoomId,
    required this.chatRoomName,
    this.chatService,
  });

  final String chatRoomId;
  final String chatRoomName;
  final ChatDataService? chatService;

  @override
  State<ChatFileCenterScreen> createState() => _ChatFileCenterScreenState();
}

class _ChatFileCenterScreenState extends State<ChatFileCenterScreen> {
  late final ChatDataService _chatService;
  MessageType? _filterType;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _nextPage = 1;
  bool _hasMore = false;
  List<Message> _files = [];

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatDataService();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await _chatService.getFileMessages(
        widget.chatRoomId,
        type: _filterType,
      );
      if (!mounted) return;
      setState(() {
        _files = page.messages;
        _nextPage = page.currentPage + 1;
        _hasMore = page.hasNext;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _chatService.getFileMessages(
        widget.chatRoomId,
        type: _filterType,
        page: _nextPage,
      );
      if (!mounted) return;
      setState(() {
        final existing = _files.map((message) => message.id).toSet();
        _files = [
          ..._files,
          ...page.messages.where((message) => !existing.contains(message.id)),
        ];
        _nextPage = page.currentPage + 1;
        _hasMore = page.hasNext;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      _showSnackBar('加载更多失败: $error', isError: true);
    }
  }

  Future<void> _openFile(Message message) async {
    try {
      final file = await _chatService.downloadFile(message);
      if (!mounted) return;
      _showSnackBar('已下载 ${file.name} (${_formatFileSize(file.bytes.length)})');
    } catch (error) {
      _showSnackBar('下载失败: $error', isError: true);
    }
  }

  void _setFilter(MessageType? type) {
    if (_filterType == type) return;
    setState(() => _filterType = type);
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.chatRoomName} 文件')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<MessageType?>(
              segments: const [
                ButtonSegment<MessageType?>(
                  value: null,
                  icon: Icon(Icons.all_inbox),
                  label: Text('全部'),
                ),
                ButtonSegment<MessageType?>(
                  value: MessageType.image,
                  icon: Icon(Icons.image),
                  label: Text('图片'),
                ),
                ButtonSegment<MessageType?>(
                  value: MessageType.file,
                  icon: Icon(Icons.insert_drive_file),
                  label: Text('文件'),
                ),
              ],
              selected: {_filterType},
              onSelectionChanged: (values) => _setFilter(values.first),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off,
                  size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              const Text('文件加载失败'),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadFiles, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_files.isEmpty) {
      return const Center(
        child: Text(
          '暂无文件',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 160) {
          _loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _loadFiles,
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: _files.length + (_isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (_isLoadingMore && index == _files.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final message = _files[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Icon(
                  message.isImageMessage
                      ? Icons.image
                      : Icons.insert_drive_file,
                  color: AppColors.primary,
                ),
              ),
              title: Text(
                message.fileName ?? message.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  message.senderName,
                  if (message.fileSize != null)
                    _formatFileSize(message.fileSize!),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.download),
              onTap: () => _openFile(message),
            );
          },
        ),
      ),
    );
  }

  String _formatFileSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }
}
