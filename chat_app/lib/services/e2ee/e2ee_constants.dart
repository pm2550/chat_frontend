// 端到端加密里前后端、新老客户端共用的几个常量（不依赖任何加密库，模型层也能引用）。

/// 消息的 encryptionVersion（服务器也只认这个值）。
const int kE2eeEncryptionVersion = 2;

/// 服务器写进 content 的占位文字：老客户端直接显示它。
const String kE2eeServerPlaceholder = '[加密消息，请更新到最新版本查看]';

/// 服务器给加密附件写的文件名（真实文件名在密文里）。
const String kE2eeServerAttachmentName = '加密附件（请更新到最新版本查看）';

/// 推送/列表里不带内容时用的文字。
const String kE2eeShortLabel = '[加密消息]';
