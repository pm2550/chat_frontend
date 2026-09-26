part of '../ai_hub_page.dart';

extension _AiHubView1Parts on _AiHubPageState {
  Widget _buildSegmentedNav() {
    return PMCard(
        elevated: false,
        padding: const EdgeInsets.all(PMSpacing.xs),
        child: Row(children: [
          for (var index = 0; index < _AiHubPageState._sections.length; index++)
            Expanded(
              child: Semantics(
                  selected: _selectedIndex == index,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    onTap: () => _selectSection(index),
                    child: AnimatedContainer(
                      duration: PMMotion.duration(context, PMMotion.medium),
                      curve: PMMotion.curveStandard,
                      padding: const EdgeInsets.symmetric(
                          vertical: PMSpacing.m, horizontal: PMSpacing.xs),
                      decoration: BoxDecoration(
                          color: _selectedIndex == index
                              ? AppColors.pixelMint
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(PMRadius.s)),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_AiHubPageState._sections[index].icon,
                                size: 18,
                                color: _selectedIndex == index
                                    ? AppColors.secondaryDark
                                    : AppColors.textSecondary),
                            const SizedBox(width: PMSpacing.s),
                            Flexible(
                                child: Text(
                                    _AiHubPageState._sections[index].label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _selectedIndex == index
                                            ? AppColors.secondaryDark
                                            : AppColors.textSecondary))),
                          ]),
                    ),
                  )),
            ),
        ]));
  }

  Widget _buildBotsTab() {
    if (_bots.isEmpty) {
      return PMEmptyState(
        icon: Icons.smart_toy_outlined,
        title: '你的第一位 AI 伙伴',
        illustration: const PMWelcomeArt(size: 152),
        subtitle: '先连接可用的 AI 服务，创建助手，再把它加入群聊。你可以为它设定名字、性格和擅长的事。',
        variant: EmptyStateVariant.illustration,
        action:
            PMButton(label: '创建助手', icon: Icons.add, onPressed: _openCreateBot),
      );
    }

    return _ResponsiveGrid(
      children: [
        for (final bot in _bots)
          PMCard(
            interactive: true,
            onTap: () => _openEditBot(bot),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _AiAvatar(
                      icon: Icons.smart_toy,
                      label: bot.botName,
                      avatarUrl: bot.botAvatar,
                      active: bot.isActive,
                    ),
                    const SizedBox(width: PMSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bot.botName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: PMSpacing.xs),
                          Text(
                            '${bot.llmProvider} · ${bot.modelName?.isNotEmpty == true ? bot.modelName : '默认模型'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PMStatusBadge(
                      status: bot.isActive
                          ? PMOnlineStatus.online
                          : PMOnlineStatus.offline,
                      label: bot.isActive ? '可用' : '停用',
                    ),
                  ],
                ),
                const SizedBox(height: PMSpacing.l),
                Text(
                  bot.systemPrompt?.trim().isNotEmpty == true
                      ? bot.systemPrompt!.trim()
                      : '尚未配置系统提示词',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const Spacer(),
                const SizedBox(height: PMSpacing.l),
                Row(
                  children: [
                    TextButton.icon(
                        onPressed: () => _openEditBot(bot),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('编辑助手')),
                    const Spacer(),
                    TextButton.icon(
                        onPressed: bot.isActive && bot.id != null
                            ? () => _joinRoomWithBot(bot)
                            : null,
                        icon: const Icon(Icons.forum_outlined, size: 16),
                        label: const Text('加入群聊')),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRoomsTab() {
    if (_rooms.isEmpty) {
      return const PMEmptyState(
        icon: Icons.forum_outlined,
        title: '还没有可配置的房间',
        subtitle: '创建群聊后，可以在这里把 Bot 加入房间并设置触发规则。',
      );
    }

    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.s),
      child: Column(
        children: [
          for (final room in _rooms)
            PMListRow(
              leading: _AiAvatar(
                icon:
                    room.type == ChatType.private ? Icons.person : Icons.groups,
                label: _aiRoomTitle(room),
                color: room.anonymousEnabled
                    ? const Color(0xFF7C3AED)
                    : AppColors.secondary,
                active: true,
              ),
              title: Text(_aiRoomTitle(room)),
              subtitle: Text(
                '${room.type.description} · ${room.effectiveMemberCount} 人 · ${room.anonymousEnabled ? '匿名已启用' : '匿名未启用'}',
              ),
              badge: room.anonymousEnabled ? '匿名' : null,
              badgeColor: const Color(0xFF7C3AED),
              trailing: PMButton(
                label: '配置 Bot',
                icon: Icons.tune,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: () => _showRoomBotSheet(room),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagesTab() {
    if (_rooms.isEmpty) {
      return const PMEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: '还没有可发送图片的会话',
        subtitle: '先创建或加入一个会话，再用积分生成图片并发到那里。',
      );
    }

    final selectedRoom = _selectedImageRoom ?? _rooms.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PMCard(
          padding: const EdgeInsets.all(PMSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImageIntro(),
              const SizedBox(height: PMSpacing.l),
              PMListRow(
                leading: _AiAvatar(
                  icon: selectedRoom.type == ChatType.private
                      ? Icons.person
                      : Icons.groups,
                  label: selectedRoom.name,
                  color: AppColors.secondary,
                  active: true,
                ),
                title: Text(
                  selectedRoom.name.isEmpty ? '未命名会话' : selectedRoom.name,
                ),
                subtitle: Text('图片将发送到这个${selectedRoom.type.description}'),
                trailing: PMButton(
                  label: '选择会话',
                  icon: Icons.swap_horiz,
                  compact: true,
                  variant: PMButtonVariant.secondary,
                  onPressed: _pickImageRoom,
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              TextField(
                controller: _imagePromptController,
                minLines: 3,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '描述你想要的图片，例如：一只蓝色玻璃杯放在雨后窗边，柔和自然光',
                  filled: true,
                  fillColor: AppColors.cloud,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              PMListRow(
                leading: const _AiAvatar(
                  icon: Icons.speed,
                  label: '快出图',
                  color: AppColors.warning,
                ),
                title: const Text('快出图'),
                subtitle: const Text('关闭 Grok prompt 扩写，直接把原始描述交给画图服务。'),
                trailing: Switch(
                  value: _imageFastMode,
                  onChanged: _imageSubmitting
                      ? null
                      : (value) => _setViewState(() => _imageFastMode = value),
                ),
              ),
              if (_imageError != null) ...[
                const SizedBox(height: PMSpacing.m),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(PMSpacing.m),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    '提交失败：$_imageError',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: PMSpacing.l),
              Wrap(
                spacing: PMSpacing.s,
                runSpacing: PMSpacing.s,
                children: [
                  PMButton(
                    label: _imageSubmitting ? '提交中' : '生成并发送',
                    icon: Icons.auto_awesome,
                    onPressed: _imageSubmitting ? null : _submitImageGeneration,
                  ),
                  PMButton(
                    label: '打开会话',
                    icon: Icons.open_in_new,
                    variant: PMButtonVariant.secondary,
                    onPressed: () => _openRoom(selectedRoom),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_latestImageJob != null) ...[
          const SizedBox(height: PMSpacing.l),
          _buildLatestImageJob(_latestImageJob!),
        ],
      ],
    );
  }

  Widget _buildImageIntro() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        const avatar = _AiAvatar(
          icon: Icons.auto_awesome,
          label: 'AI 画图',
          color: Color(0xFF7C3AED),
          active: true,
        );
        const copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 点数画图',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: PMSpacing.xs),
            Text(
              '生成完成后会作为图片消息发送到选中的会话，失败会自动退回积分。',
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        );
        if (compact) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  SizedBox(width: PMSpacing.m),
                  Expanded(child: copy),
                ],
              ),
              SizedBox(height: PMSpacing.m),
              PMCostPreviewChip(featureKey: 'image_generation'),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            SizedBox(width: PMSpacing.m),
            Expanded(child: copy),
            PMCostPreviewChip(featureKey: 'image_generation'),
          ],
        );
      },
    );
  }

  Widget _buildLatestImageJob(_ImageGenerationJob job) {
    final status = job.message.isImageGenerationDone
        ? '已完成'
        : job.message.isImageGenerationFailed
            ? '生成失败'
            : '生成中';
    final color = job.message.isImageGenerationDone
        ? AppColors.success
        : job.message.isImageGenerationFailed
            ? AppColors.error
            : AppColors.warning;

    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PMChip(
                label: status,
                icon: job.message.isImageGenerationDone
                    ? Icons.check_circle
                    : job.message.isImageGenerationFailed
                        ? Icons.error_outline
                        : Icons.hourglass_top,
                selected: true,
                color: color,
              ),
              const SizedBox(width: PMSpacing.s),
              Expanded(
                child: Text(
                  _aiRoomTitle(job.room),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PMButton(
                label: '去会话查看',
                icon: Icons.open_in_new,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: () => _openRoom(job.room),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.m),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: MessageBubble(
                message: job.message,
                isMe: true,
                showAvatar: false,
                onOpenAttachment: (_) async => _openRoom(job.room),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
