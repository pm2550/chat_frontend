part of '../chat_screen.dart';

extension _ChatScreenFilesPanelParts on _ChatScreenState {
  Widget _buildFilesPanel() {
    final files = _messages
        .where((message) => message.fileUrl?.isNotEmpty == true)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PMChip(
                label: '全部', icon: Icons.inventory_2_rounded, selected: true),
            PMChip(label: '图片', icon: Icons.image_rounded),
            PMChip(label: '文档', icon: Icons.description_rounded),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: files.isEmpty
              ? const PMEmptyState(
                  icon: Icons.folder_off_rounded,
                  title: '暂无文件',
                  subtitle: '聊天里的图片、文档和音频会汇总到这里。',
                )
              : GridView.builder(
                  itemCount: files.take(12).length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  itemBuilder: (context, index) {
                    final message = files[index];
                    return PMAttachmentCard(
                      type: _attachmentTypeForMessage(message),
                      name: message.fileName ?? message.content,
                      sizeText: message.fileSize == null
                          ? null
                          : _formatFileSize(message.fileSize!),
                      forcePreview: message.isImageMessage,
                      onTap: () => _openAttachment(message),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        PMButton(
          label: '进入完整文件中心',
          icon: Icons.open_in_new,
          variant: PMButtonVariant.secondary,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatFileCenterScreen(
                  chatRoomId: _chat.id,
                  chatRoomName: _chat.name,
                  chatService: _chatService,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
