/// 把输入框的变化节流成"正在输入"事件。
///
/// 服务器 3 秒没收到续期就认为对方停止输入，所以持续输入时每 [refreshInterval]
/// 续一次；内容清空、发送、输入框失焦时立刻发"停止"。
class TypingIndicatorSender {
  TypingIndicatorSender({
    required void Function(bool isTyping) send,
    DateTime Function()? clock,
    this.refreshInterval = const Duration(seconds: 2),
  })  : _send = send,
        _clock = clock ?? DateTime.now;

  final void Function(bool isTyping) _send;
  final DateTime Function() _clock;
  final Duration refreshInterval;

  bool _active = false;
  DateTime? _lastSentAt;
  String _lastText = '';

  bool get isActive => _active;

  /// 输入框内容变了。只移动光标、内容没变不算输入。
  void onTextChanged(String text) {
    if (text == _lastText) return;
    _lastText = text;
    if (text.trim().isEmpty) {
      stop();
      return;
    }
    final now = _clock();
    final lastSentAt = _lastSentAt;
    if (_active &&
        lastSentAt != null &&
        now.difference(lastSentAt) < refreshInterval) {
      return;
    }
    _active = true;
    _lastSentAt = now;
    _send(true);
  }

  /// 发送、清空、失焦、离开页面时调用。
  void stop() {
    if (!_active) return;
    _active = false;
    _lastSentAt = null;
    _send(false);
  }
}
