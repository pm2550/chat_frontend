# 聊天应用 - Chat App

一个功能完整的Flutter聊天应用，支持iOS、Android和华为系统部署。

## 功能特性

### 🎨 界面设计
- 现代化Material Design 3设计风格
- 优雅的渐变色彩和动画效果
- 响应式布局，适配不同屏幕尺寸
- 支持深色/浅色主题切换

### 🔐 用户认证
- 用户登录/注册功能
- 第三方登录支持（Google、Apple、微信）
- 安全的表单验证
- 记住登录状态

### 💬 聊天功能
- 实时消息发送和接收
- 支持多种消息类型：
  - 文本消息
  - 图片消息
  - 文件消息
  - 语音消息
  - 位置消息
- 消息状态显示（发送中、已发送、已送达、已读）
- 消息时间戳显示

### 👥 联系人管理
- 联系人列表
- 添加/删除联系人
- 在线状态显示
- 联系人搜索

### 🗂️ 聊天管理
- 私聊和群聊支持
- 聊天列表
- 消息搜索
- 聊天置顶/静音
- 未读消息计数

### ⚙️ 个人设置
- 个人资料编辑
- 隐私设置
- 通知设置
- 语言设置

## 技术架构

### 状态管理
- **Riverpod** - 现代化的状态管理解决方案
- **Provider** - 依赖注入和状态共享

### UI框架
- **Flutter** - 跨平台UI框架
- **Material Design 3** - 现代化设计系统
- **Google Fonts** - 字体支持

### 网络通信
- **Dio** - HTTP客户端
- **Socket.IO** - 实时通信
- **Connectivity Plus** - 网络状态检测

### 本地存储
- **SQLite** - 本地数据库
- **SharedPreferences** - 轻量级存储

### 媒体处理
- **Image Picker** - 图片选择
- **File Picker** - 文件选择
- **Cached Network Image** - 图片缓存

### 其他功能
- **Permission Handler** - 权限管理
- **Device Info Plus** - 设备信息
- **Package Info Plus** - 应用信息
- **Share Plus** - 分享功能
- **Timeago** - 时间格式化

## 项目结构

```
lib/
├── constants/           # 常量定义
│   └── app_colors.dart # 颜色主题
├── models/             # 数据模型
│   ├── user.dart      # 用户模型
│   ├── message.dart   # 消息模型
│   └── chat.dart      # 聊天模型
├── screens/            # 页面组件
│   ├── splash_screen.dart      # 启动页
│   ├── auth/                   # 认证相关页面
│   │   └── login_screen.dart   # 登录页
│   ├── home/                   # 主页相关页面
│   │   ├── home_screen.dart    # 主页框架
│   │   ├── chat_list_page.dart # 聊天列表
│   │   ├── contacts_page.dart  # 联系人页面
│   │   └── profile_page.dart   # 个人资料页面
│   └── chat/
│       └── chat_screen.dart    # 聊天界面
├── widgets/            # 通用组件
│   └── message_bubble.dart     # 消息气泡
└── main.dart          # 应用入口
```

## 平台支持

### iOS 
- iOS 12.0 及以上版本
- 支持iPhone和iPad
- 适配刘海屏和Face ID

### Android
- Android 5.0 (API Level 21) 及以上版本
- 支持手机和平板
- 兼容各种屏幕尺寸

### 华为系统
- HarmonyOS 2.0 及以上版本
- 支持华为手机和平板
- 完全兼容华为生态

## 安装运行

### 环境要求
- Flutter SDK 3.5.0 或更高版本
- Dart SDK 3.0.0 或更高版本
- Android Studio / Xcode（用于构建原生应用）

### 安装步骤

1. 克隆项目
```bash
git clone [project-url]
cd chat_app
```

2. 安装依赖
```bash
flutter pub get
```

3. 运行应用
```bash
# 在调试模式运行
flutter run

# 在特定设备运行
flutter run -d <device-id>
```

### 构建发布版本

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# 华为系统
flutter build apk --release
```

## 配置说明

### Android 配置
在 `android/app/src/main/AndroidManifest.xml` 中配置必要的权限：
- 网络访问权限
- 相机权限
- 存储权限
- 定位权限

### iOS 配置
在 `ios/Runner/Info.plist` 中配置必要的权限：
- 相机使用权限
- 照片库访问权限
- 麦克风使用权限
- 定位服务权限

## 开发指南

### 添加新功能
1. 在 `models/` 目录下定义数据模型
2. 在 `screens/` 目录下创建页面组件
3. 在 `widgets/` 目录下创建可复用组件
4. 更新路由配置

### 自定义主题
在 `constants/app_colors.dart` 中修改颜色配置：
```dart
static const Color primary = Color(0xFF2196F3);
static const Color secondary = Color(0xFF03DAC6);
```

### 多语言支持
1. 在 `pubspec.yaml` 中添加 `flutter_localizations`
2. 创建 `l10n/` 目录存放翻译文件
3. 配置支持的语言

## 后续开发计划

- [ ] 实现后端API集成
- [ ] 添加语音/视频通话功能
- [ ] 支持消息加密
- [ ] 添加表情包和贴纸
- [ ] 实现消息转发功能
- [ ] 添加群聊管理功能
- [ ] 支持消息撤回
- [ ] 实现离线消息同步
- [ ] 添加消息推送
- [ ] 支持多端同步

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 贡献

欢迎提交 Issues 和 Pull Requests 来改进这个项目。

## 联系方式

如有问题或建议，请通过以下方式联系：
- Email: developer@example.com
- GitHub: [project-github-url]

---

**注意**: 这是一个演示项目，部分功能需要集成真实的后端服务才能完全使用。
