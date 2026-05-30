import 'package:flutter/material.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/message.dart';
import '../../services/chat_data_service.dart';
import '../../services/file_save.dart' as file_save;
import '../../widgets/pm_brand.dart';

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
  final TextEditingController _searchController = TextEditingController();
  MessageType? _filterType;
  String _searchQuery = '';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Message> get _visibleFiles {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _files;
    return _files.where((message) {
      return [
        message.fileName,
        message.content,
        message.senderName,
        message.fileType,
      ].whereType<String>().any((value) => value.toLowerCase().contains(query));
    }).toList();
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
      final saved = await file_save.saveBytesAsFile(
        bytes: file.bytes,
        name: file.name,
        mimeType: file.mimeType ?? message.fileType,
      );
      if (!mounted) return;
      _showSnackBar(saved
          ? '已保存 ${file.name}'
          : '已取回 ${file.name} (${_formatFileSize(file.bytes.length)})');
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
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Scaffold(
      body: PMChatPattern(
        dense: !isWide,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isWide ? PMSpacing.xxl : PMSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PMPageHeader(
                  title: '${widget.chatRoomName} 文件',
                  subtitle: '集中查看这个会话里的图片、文档和附件',
                  leading: const _FileCenterHeaderIcon(),
                  actions: [
                    PMButton(
                      label: '返回聊天',
                      icon: Icons.arrow_back,
                      compact: true,
                      variant: PMButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    PMButton(
                      label: '刷新',
                      icon: Icons.refresh,
                      compact: true,
                      variant: PMButtonVariant.secondary,
                      onPressed: _isLoading ? null : _loadFiles,
                    ),
                  ],
                ),
                const SizedBox(height: PMSpacing.xl),
                _buildFilterBar(),
                const SizedBox(height: PMSpacing.l),
                Expanded(child: _buildBody(isWide: isWide)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.l),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索文件名、发送人或类型',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
              filled: true,
              fillColor: AppColors.cloud.withValues(alpha: 0.55),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PMRadius.s),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: PMSpacing.m),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: PMSpacing.s,
                  runSpacing: PMSpacing.s,
                  children: [
                    PMChip(
                      label: '全部',
                      icon: Icons.all_inbox_outlined,
                      selected: _filterType == null,
                      onTap: () => _setFilter(null),
                    ),
                    PMChip(
                      label: '图片',
                      icon: Icons.image_outlined,
                      selected: _filterType == MessageType.image,
                      color: AppColors.secondary,
                      onTap: () => _setFilter(MessageType.image),
                    ),
                    PMChip(
                      label: '视频',
                      icon: Icons.movie_outlined,
                      selected: _filterType == MessageType.video,
                      color: AppColors.accent,
                      onTap: () => _setFilter(MessageType.video),
                    ),
                    PMChip(
                      label: '文档',
                      icon: Icons.insert_drive_file_outlined,
                      selected: _filterType == MessageType.file,
                      color: AppColors.primary,
                      onTap: () => _setFilter(MessageType.file),
                    ),
                    PMChip(
                      label: '音频',
                      icon: Icons.graphic_eq,
                      selected: _filterType == MessageType.voice,
                      color: AppColors.warning,
                      onTap: () => _setFilter(MessageType.voice),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PMSpacing.m),
              Text(
                _isLoading ? '加载中' : '${_visibleFiles.length} 项',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody({required bool isWide}) {
    final visibleFiles = _visibleFiles;
    if (_isLoading) {
      return _buildLoadingGrid(isWide: isWide);
    }
    if (_error != null) {
      return PMErrorState(
        title: '文件加载失败',
        message: _error!,
        onRetry: _loadFiles,
      );
    }
    if (visibleFiles.isEmpty) {
      return PMEmptyState(
        icon: Icons.folder_off_outlined,
        title: _files.isEmpty ? '暂无文件' : '没有找到相关文件',
        subtitle: _files.isEmpty ? '聊天中发送图片或附件后，会自动汇总到这里。' : '换一个关键词或切回全部类型再试。',
        variant: EmptyStateVariant.illustration,
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
        child: isWide ? _buildGrid(visibleFiles) : _buildList(visibleFiles),
      ),
    );
  }

  Widget _buildLoadingGrid({required bool isWide}) {
    if (!isWide) {
      return ListView.separated(
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: PMSpacing.m),
        itemBuilder: (_, __) => PMSkeleton.row(height: 74),
      );
    }
    return GridView.builder(
      itemCount: 8,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisSpacing: PMSpacing.l,
        crossAxisSpacing: PMSpacing.l,
        childAspectRatio: 1.22,
      ),
      itemBuilder: (_, __) => PMSkeleton.card(height: 180),
    );
  }

  Widget _buildGrid(List<Message> files) {
    final itemCount = files.length + (_isLoadingMore ? 1 : 0);
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: PMSpacing.xl),
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: PMSpacing.l,
        crossAxisSpacing: PMSpacing.l,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, index) {
        if (_isLoadingMore && index == files.length) {
          return PMSkeleton.card(height: 180);
        }
        final message = files[index];
        return _FileCenterTile(
          message: message,
          sizeText: message.fileSize == null
              ? null
              : _formatFileSize(message.fileSize!),
          onTap: () => _openFile(message),
        );
      },
    );
  }

  Widget _buildList(List<Message> files) {
    final itemCount = files.length + (_isLoadingMore ? 1 : 0);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: PMSpacing.xl),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: PMSpacing.m),
      itemBuilder: (context, index) {
        if (_isLoadingMore && index == files.length) {
          return PMSkeleton.row(height: 74);
        }
        final message = files[index];
        return PMCard(
          padding: EdgeInsets.zero,
          interactive: true,
          elevated: false,
          onTap: () => _openFile(message),
          child: PMListRow(
            leading: _FileIcon(message: message),
            title: Text(message.fileName ?? message.content),
            subtitle: Text(
              [
                message.senderName,
                if (message.fileSize != null)
                  _formatFileSize(message.fileSize!),
                _formatDate(message.timestamp),
              ].join(' · '),
            ),
            trailing: const Icon(
              Icons.download_outlined,
              color: AppColors.textSecondary,
            ),
          ),
        );
      },
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

class _FileCenterHeaderIcon extends StatelessWidget {
  const _FileCenterHeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(PMRadius.l),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: const Icon(
        Icons.folder_special_outlined,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _FileCenterTile extends StatelessWidget {
  const _FileCenterTile({
    required this.message,
    required this.sizeText,
    required this.onTap,
  });

  final Message message;
  final String? sizeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = message.fileName ?? message.content;
    final fileUrl = message.fileUrl;
    final publicThumbnail = message.isImageMessage &&
        fileUrl != null &&
        !ApiConstants.requiresAuthHeaderForFile(fileUrl);
    return PMAttachmentCard(
      type: _attachmentType(message),
      thumbnail: publicThumbnail ? ApiConstants.resolveFileUrl(fileUrl) : null,
      forcePreview: message.isImageMessage || message.isVideoMessage,
      name: name,
      sizeText: [
        if (sizeText != null) sizeText,
        if (message.senderName.isNotEmpty) message.senderName,
      ].join(' · '),
      onTap: onTap,
    );
  }
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final type = _attachmentType(message);
    final color = switch (type) {
      AttachmentType.image => AppColors.secondary,
      AttachmentType.video => AppColors.accent,
      AttachmentType.voice => AppColors.warning,
      AttachmentType.location => AppColors.success,
      AttachmentType.file => AppColors.primary,
    };
    final icon = switch (type) {
      AttachmentType.image => Icons.image_outlined,
      AttachmentType.video => Icons.movie_outlined,
      AttachmentType.voice => Icons.graphic_eq,
      AttachmentType.location => Icons.location_on_outlined,
      AttachmentType.file => Icons.insert_drive_file_outlined,
    };
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(PMRadius.m),
      ),
      child: Icon(icon, color: color),
    );
  }
}

AttachmentType _attachmentType(Message message) {
  if (message.isImageMessage) return AttachmentType.image;
  if (message.isVideoMessage) return AttachmentType.video;
  if (message.isVoiceMessage) return AttachmentType.voice;
  if (message.isLocationMessage) return AttachmentType.location;
  return AttachmentType.file;
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final local = date.toLocal();
  if (now.year == local.year &&
      now.month == local.month &&
      now.day == local.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}
