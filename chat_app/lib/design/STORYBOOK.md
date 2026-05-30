# PM chat Design System Storybook

P0 设计系统只提供通用视觉组件，不触碰后端协议、service/model 层，也不直接改业务页面。

## Import

```dart
import 'package:chat_app/design/design.dart';
```

## Tokens

```dart
const gap = PMSpacing.l;
final radius = BorderRadius.circular(PMRadius.m);
const shadow = PMElevation.card;
const duration = PMMotion.medium;
```

## PMCard

统一卡片容器，替换散落的 `Container + BoxDecoration`。

```dart
PMCard(
  interactive: true,
  onTap: () {},
  child: const Text('工作区文件'),
)
```

## PMPageHeader

页面标题、副标题、actions 和搜索槽统一入口。

```dart
PMPageHeader(
  title: '设置',
  subtitle: '管理隐私、通知和账号偏好',
  actions: [
    PMButton(label: '保存', onPressed: () {}),
  ],
  search: TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search))),
)
```

## PMSectionCard

设置项、成员组、账号操作等区域分组。

```dart
PMSectionCard(
  title: '隐私安全',
  subtitle: '端到端加密和登录安全',
  children: [
    PMListRow(
      leading: Icon(Icons.lock_outline),
      title: Text('端到端加密'),
      subtitle: Text('为新消息生成本地密钥'),
      trailing: Switch(value: true, onChanged: (_) {}),
    ),
  ],
)
```

## PMListRow

替代大多数 `ListTile`，自带 hover、badge、长按和 action 槽。

```dart
PMListRow(
  leading: PMUserAvatar(user: user, showOnlineDot: true),
  title: Text(user.displayName),
  subtitle: Text('@${user.username}'),
  badge: '3',
  onTap: () {},
)
```

## PMUserAvatar + PMStatusBadge

头像统一处理图片、fallback 字母、群组圆角和在线状态点。

```dart
PMUserAvatar(user: user, size: 48, showOnlineDot: true)
PMStatusBadge(status: PMOnlineStatus.online)
```

## PMEmptyState / PMErrorState

列表空态和加载失败统一，不再只靠 snackbar。

```dart
PMEmptyState(
  icon: Icons.forum_outlined,
  title: '暂无聊天',
  subtitle: '发起第一段对话后会显示在这里。',
  action: PMButton(label: '新建群聊', onPressed: () {}),
)

PMErrorState(
  message: 'Forbidden',
  onRetry: loadAgain,
)
```

## PMSkeleton

加载骨架屏，内置 shimmer 动画。

```dart
Column(
  children: const [
    PMSkeleton.row(),
    SizedBox(height: PMSpacing.s),
    PMSkeleton.card(height: 160),
  ],
)
```

## PMAttachmentCard

聊天、文件中心和工作区复用的附件展示。

```dart
PMAttachmentCard(
  type: AttachmentType.file,
  name: 'proposal.pdf',
  sizeText: '2.4 MB',
  progress: 0.72,
  onTap: openFile,
)
```

## PMButton

主、次、危险、链接四档按钮。

```dart
PMButton(label: '保存', icon: Icons.check, onPressed: save)
PMButton(
  label: '删除',
  icon: Icons.delete_outline,
  variant: PMButtonVariant.danger,
  onPressed: delete,
)
```

## PMDialogHeader

Dialog / bottom sheet 顶部统一样式。

```dart
PMDialogHeader(
  title: '成员权限',
  subtitle: '管理谁可以查看或编辑当前文件夹',
  onClose: () => Navigator.pop(context),
)
```

## PMProgressStrip

顶部细线进度，用于 E2EE 生成、上传、扫描等持续任务。

```dart
PMProgressStrip(
  label: '正在生成端到端加密密钥...',
  progress: null,
)
```

## PMChip

筛选和标签。

```dart
Wrap(
  spacing: PMSpacing.s,
  children: [
    PMChip(label: '全部', selected: true),
    PMChip(label: '图片', icon: Icons.image_outlined),
  ],
)
```

## Catalog Preview

设计预览图在同目录:

- `catalog_preview.svg`

下一阶段 P1 页面重做时，业务页面应优先 import `design.dart`，再逐步替换裸 `ListTile`、散装 `Container` 和零散空态。
