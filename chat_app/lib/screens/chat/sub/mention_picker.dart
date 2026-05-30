part of '../chat_screen.dart';

extension _ChatScreenCommandParts on _ChatScreenState {
  void _showSlashCommandPanel() {
    final text = _messageController.text.trim();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PMCard(
            radius: PMRadius.xl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PMDialogHeader(
                  title: 'Agent 命令',
                  subtitle: '把当前输入作为 prompt，或直接运行会话快捷任务。',
                ),
                const SizedBox(height: 12),
                _buildSlashCommandRow(
                  command: '/ask',
                  title: '问 AI',
                  subtitle: text.isEmpty ? '使用输入框内容提问' : text,
                  icon: Icons.psychology_alt_outlined,
                  onTap: () => _runAgentCommand('ask', text),
                ),
                _buildSlashCommandRow(
                  command: '/draft',
                  title: '生成草稿',
                  subtitle: '生成文档草稿，并在后端配置后写入资料库',
                  icon: Icons.description_outlined,
                  onTap: () => _runAgentCommand('draft', text),
                ),
                _buildSlashCommandRow(
                  command: '/summarize',
                  title: '总结最近消息',
                  subtitle: '总结最近 50 条上下文',
                  icon: Icons.summarize_outlined,
                  onTap: () => _runAgentCommand('summarize', text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlashCommandRow({
    required String command,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return PMListRow(
      leading: CircleAvatar(
        backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
        child: Icon(icon, color: AppColors.secondaryDark),
      ),
      title: Text('$command · $title'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _runAgentCommand(String kind, String prompt) async {
    Navigator.of(context).pop();
    final resolvedPrompt = switch (kind) {
      'summarize' => prompt.isEmpty ? '总结最近 50 条消息' : prompt,
      'draft' => prompt.isEmpty ? '根据当前会话生成文档草稿' : prompt,
      _ => prompt,
    };
    if (resolvedPrompt.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入 prompt，或选择总结命令')),
      );
      return;
    }

    final tempTask = AgentTask(
      id: 'local-agent-${DateTime.now().microsecondsSinceEpoch}',
      chatRoomId: _chat.id,
      requestedById: _authService.currentUser?.id ?? '',
      prompt: resolvedPrompt,
      status: AgentTaskStatus.running,
      createdAt: DateTime.now(),
    );
    _setViewState(() {
      _isRunningAgentTask = true;
      _agentTasks.add(tempTask);
      _messageController.clear();
      _isTyping = false;
    });
    _scrollToBottom();

    try {
      final task = await _chatService.createAgentTask(
        _chat.id,
        resolvedPrompt,
        kind: kind,
      );
      if (!mounted) return;
      _setViewState(() {
        final index = _agentTasks.indexWhere((item) => item.id == tempTask.id);
        if (index == -1) {
          _agentTasks.add(task);
        } else {
          _agentTasks[index] = task;
        }
        _isRunningAgentTask = false;
      });
      if (task.resultMessage != null) {
        _upsertMessage(task.resultMessage!.chatRoomId.isEmpty
            ? task.resultMessage!.copyWith(chatRoomId: _chat.id)
            : task.resultMessage!);
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _setViewState(() {
        final index = _agentTasks.indexWhere((item) => item.id == tempTask.id);
        if (index != -1) {
          _agentTasks[index] = AgentTask(
            id: tempTask.id,
            chatRoomId: tempTask.chatRoomId,
            requestedById: tempTask.requestedById,
            prompt: tempTask.prompt,
            status: AgentTaskStatus.failed,
            errorMessage: e.toString(),
            createdAt: tempTask.createdAt,
          );
        }
        _isRunningAgentTask = false;
      });
    }
  }
}
