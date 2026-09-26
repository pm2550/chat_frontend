# PM Chat UI 重构 · 1.1.54

## 问题与结果

原桌面消息页以统计卡片为中心，进入聊天后会话列表消失，左右资料面板重复展示人物资料。本次将桌面改成紧凑主导航、常驻会话列表和聊天区域；资料由顶部入口按需打开。手机保留底部导航，输入栏在窄屏常驻表情，匿名身份仅在会话支持时显示。

- 消息：全部、未读、@我筛选；搜索、会话菜单和通知入口保留。
- 聊天：一屏切换会话；资料抽屉；桌面工具栏与输入框分行；保留附件队列、引用回复、通话、匿名、加密和实时同步。
- 联系人：紧凑快捷操作，统一头像与列表行，保留好友请求、分组和会话管理。
- AI：助手 / 群聊 / 画图短标签；连接服务入口；已有可用助手可选择群聊、加入后直接打开聊天。
- 个人页：收藏、聊天装扮、二维码前置；状态放入资料头部；账户元数据折叠呈现。
- 工作区：统一标题与空状态；选择资料库后才显示上传按钮；较窄桌面使用预览弹层，避免三栏挤压。
- 外观：统一靛蓝主色、绿色 AI 标识、表面、圆角和阴影；默认聊天背景改为淡紫渐变，修复背景绘制越界；保留自选背景、气泡和头像框。
- 欢迎插画：静态 WebP，42,908 字节，解码宽度限制 512px。无持续动画、视频或新增运行时绘图库。
- 交互：公共卡片与列表使用 Material 键盘交互；新导航、卡片与分段控件尊重系统减少动态效果设置。

## 代码组织

沿用 `lib/design` 的 PM 组件。大页面通过同库 `part` 拆为数据、操作、视图片段，避免复制业务逻辑。聊天与会话列表的大型测试同样拆成同库片段，保留全部原有测试。

主要路径：

- `lib/constants/app_colors.dart`、`app_brand.dart`
- `lib/design/pm_theme.dart`、`tokens.dart`、`pm_card.dart`、`pm_list_row.dart`、`pm_page_header.dart`、`pm_empty_state.dart`、`pm_chat_customization.dart`
- `lib/widgets/pm_navigation_rail.dart`、`pm_welcome_art.dart`、`pm_brand.dart`、`pm_responsive.dart`
- `lib/screens/home/` 与 `sub/`
- `lib/screens/chat/chat_screen.dart` 与 `sub/`
- `lib/screens/ai/ai_hub_page.dart` 与 `sub/`
- `lib/screens/workspace/workspace_page.dart` 与 `sub/`
- `lib/screens/auth/login_screen.dart`、`lib/screens/settings/chat_preferences_screen.dart`
- `test/screens/ui_refactor_test.dart` 与相关页面测试

没有新增接口、数据库迁移或第三方运行时依赖。用户已有的 `reply_preview_strip.dart` 改动完整保留，未重写其逻辑。

## 验证与发布

基线：907 项测试通过；基线分析有一处已弃用语义匹配器提示，本次已消除。

最终静态分析 0 issues，912 项测试全部通过，正式 Web 构建成功。已发布版本 1.1.54+11054，构建标识 `4ba2c3be6d4af5b1fd60`；正常公网域名已返回新版本。

详细检查结果与发布记录见本地交付记录 `/home/ubuntu/pmchat-ui-refactor-20260926/DELIVERY.md`。浏览器截图使用隔离示例账号与消息，API 请求由浏览器拦截；没有读取或发送真实聊天。截图验证针对网页布局，不能代替真机软键盘或真实通话质量测试。

实际 Nginx 服务的是 `releases/current`，不是 `build/web`。候选在 `build/web` 构建、核验后复制为不可变版本，再原子切换 `current`；`previous` 保留上一版。沿用已有发布方式与网络配置。

回滚：在应用目录运行 `bash scripts/rollback_web_release.sh`。

## 欢迎插画来源

内置 image_gen 工具生成，技能 `/home/ubuntu/.codex/skills/.system/imagegen/SKILL.md`。最终项目资源：`assets/images/pmchat-welcome-v1.webp`。只做尺寸和编码优化，不修改生成画面。

提示词见 `docs/PMCHAT_WELCOME_PROMPT.md`。
