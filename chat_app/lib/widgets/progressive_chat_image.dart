import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 聊天气泡里一张图取到的字节和显示尺寸（摆正后的宽高，用来定气泡大小）。
class ChatImageData {
  const ChatImageData({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// 聊天图片的内存缓存：按地址存"正在取"的请求和"已经取到"的结果。
///
/// 取到的结果可以同步拿（[peek]）：气泡滑出去再滑回来直接画，不闪加载圈，换过清晰图的也不会
/// 先闪一下缩略图。按条数和总字节数淘汰最久没用的（清晰图一张几百 KB，只按条数会把内存撑大）。
class ChatImageCache {
  ChatImageCache({this.maxEntries = 80, this.maxBytes = 48 * 1024 * 1024});

  static final ChatImageCache shared = ChatImageCache();

  final int maxEntries;
  final int maxBytes;
  final Map<String, Future<ChatImageData>> _pending = {};
  final LinkedHashMap<String, ChatImageData> _resolved =
      LinkedHashMap<String, ChatImageData>();
  int _resolvedBytes = 0;

  /// 已经取到的图（同时标记为最近用过）；没有返回 null。
  ChatImageData? peek(String key) {
    final hit = _resolved.remove(key);
    if (hit == null) return null;
    _resolved[key] = hit;
    return hit;
  }

  /// 取图：已取到的直接返回，正在取的复用同一个请求，失败的不留在缓存里（下次还能重试）。
  Future<ChatImageData> load(
    String key,
    Future<ChatImageData> Function() fetch,
  ) {
    final hit = peek(key);
    if (hit != null) return Future.value(hit);
    final pending = _pending[key];
    if (pending != null) return pending;

    late final Future<ChatImageData> operation;
    operation = fetch().then(
      (data) {
        if (identical(_pending[key], operation)) {
          _pending.remove(key);
          _store(key, data);
        }
        return data;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_pending[key], operation)) {
          _pending.remove(key);
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _pending[key] = operation;
    return operation;
  }

  void _store(String key, ChatImageData data) {
    final previous = _resolved.remove(key);
    if (previous != null) _resolvedBytes -= previous.bytes.length;
    _resolved[key] = data;
    _resolvedBytes += data.bytes.length;
    while (_resolved.length > 1 &&
        (_resolved.length > maxEntries || _resolvedBytes > maxBytes)) {
      final oldest = _resolved.keys.first;
      _resolvedBytes -= _resolved.remove(oldest)!.bytes.length;
    }
  }

  void clear() {
    _pending.clear();
    _resolved.clear();
    _resolvedBytes = 0;
  }
}

/// 清晰图的后台下载队列：同时最多 [maxConcurrent] 张，后进先出——
/// 用户此刻停下来看的图（最后排进来的）先下；排着队还没开始就被滑走的会被撤掉（见 [ChatImageUpgradeTicket.cancel]）。
class ChatImageUpgradeQueue {
  ChatImageUpgradeQueue({this.maxConcurrent = 2});

  static ChatImageUpgradeQueue shared = ChatImageUpgradeQueue();

  /// 换一个干净的队列（测试之间用：上一个测试没跑完的任务不影响下一个）。
  static void resetShared({int maxConcurrent = 2}) {
    shared = ChatImageUpgradeQueue(maxConcurrent: maxConcurrent);
  }

  final int maxConcurrent;
  int _running = 0;
  final List<ChatImageUpgradeTicket> _waiting = [];

  int get running => _running;
  int get waiting => _waiting.length;

  ChatImageUpgradeTicket schedule(Future<void> Function() job) {
    final ticket = ChatImageUpgradeTicket._(this, job);
    _waiting.add(ticket);
    _pump();
    return ticket;
  }

  void _pump() {
    while (_running < maxConcurrent && _waiting.isNotEmpty) {
      final ticket = _waiting.removeLast();
      ticket._started = true;
      _running++;
      Future<void>.sync(ticket._job)
          .catchError((Object _) {})
          .whenComplete(() {
        _running--;
        _pump();
      });
    }
  }
}

class ChatImageUpgradeTicket {
  ChatImageUpgradeTicket._(this._queue, this._job);

  final ChatImageUpgradeQueue _queue;
  final Future<void> Function() _job;
  bool _started = false;

  bool get started => _started;

  /// 还没开始就撤出队列；已经在下载的让它下完（字节已经在路上，下完进缓存，滑回来能直接用）。
  void cancel() {
    if (!_started) _queue._waiting.remove(this);
  }
}

/// 聊天气泡里的图：先显示 [url]（缩略图），气泡在屏幕上停稳 [settleDelay] 以后，
/// 在后台排队下载 [sharpUrl]（清晰图），解码好了淡入替换。
///
/// - 快速滑过、只在列表预加载区里（没真正上屏）的气泡不会去下清晰图；
/// - 排队中又被滑出屏幕的撤掉，气泡销毁时也撤掉；
/// - 取到的图都进 [ChatImageCache]，滑回来直接画清晰图，不再先闪缩略图；
/// - 清晰图取失败就一直用缩略图，不打扰。
class ProgressiveChatImage extends StatefulWidget {
  const ProgressiveChatImage({
    super.key,
    required this.url,
    required this.load,
    required this.peek,
    required this.builder,
    required this.placeholder,
    required this.errorBuilder,
    this.sharpUrl,
    this.queue,
    this.settleDelay = const Duration(milliseconds: 350),
  });

  final String url;
  final String? sharpUrl;

  /// 按地址取图（走缓存）。
  final Future<ChatImageData> Function(String url) load;

  /// 按地址同步查缓存。
  final ChatImageData? Function(String url) peek;

  /// 把图包成气泡里的样子：[layout] 定尺寸，[image] 是叠好（缩略图 + 淡入的清晰图）的图层。
  final Widget Function(BuildContext context, ChatImageData layout, Widget image)
      builder;
  final WidgetBuilder placeholder;
  final WidgetBuilder errorBuilder;

  /// 为空时用 [ChatImageUpgradeQueue.shared]。
  final ChatImageUpgradeQueue? queue;
  final Duration settleDelay;

  @override
  State<ProgressiveChatImage> createState() => _ProgressiveChatImageState();
}

class _ProgressiveChatImageState extends State<ProgressiveChatImage> {
  ChatImageData? _base;
  ChatImageData? _sharp;
  bool _baseFailed = false;
  bool _sharpFailed = false;

  /// 清晰图淡入完了：不再叠着画缩略图（透明 PNG 的缩略图会从透明处透出来）。
  bool _fadeDone = false;
  ChatImageUpgradeTicket? _ticket;
  Timer? _settleTimer;
  ScrollableState? _scrollable;
  ScrollPosition? _position;

  ChatImageUpgradeQueue get _queue =>
      widget.queue ?? ChatImageUpgradeQueue.shared;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.maybeOf(context);
    final position = _scrollable?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_handleScroll);
      _position = position?..addListener(_handleScroll);
    }
  }

  @override
  void didUpdateWidget(covariant ProgressiveChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.sharpUrl != widget.sharpUrl) {
      _cancelUpgrade();
      _base = null;
      _sharp = null;
      _baseFailed = false;
      _sharpFailed = false;
      _fadeDone = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_handleScroll);
    _cancelUpgrade();
    super.dispose();
  }

  void _resolve() {
    final sharpUrl = widget.sharpUrl;
    final sharp = sharpUrl == null ? null : widget.peek(sharpUrl);
    if (sharp != null) {
      // 之前已经换过清晰图：直接画它，不再经过缩略图。
      _sharp = sharp;
      _fadeDone = true;
      return;
    }
    final base = widget.peek(widget.url);
    if (base != null) {
      _base = base;
      _scheduleVisibilityCheck();
      return;
    }
    final url = widget.url;
    widget.load(url).then((data) {
      if (!mounted || widget.url != url) return;
      setState(() => _base = data);
      _scheduleVisibilityCheck();
    }, onError: (Object _) {
      if (!mounted || widget.url != url) return;
      setState(() => _baseFailed = true);
      // 缩略图取不到（例如本地缓存的消息里还是被回填换掉的老缩略图地址）：有清晰图就直接用它。
      _scheduleVisibilityCheck();
    });
  }

  bool get _wantsUpgrade =>
      widget.sharpUrl != null &&
      _sharp == null &&
      !_sharpFailed &&
      _ticket == null &&
      (_base != null || _baseFailed);

  void _scheduleVisibilityCheck() {
    if (!_wantsUpgrade) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(widget.settleDelay, _checkVisibility);
  }

  /// 滚动中一直往后推：停稳了才看要不要换，快速翻历史不会一路排下载。
  /// （滚动回调可能在布局中途触发，这里不碰几何信息。）
  void _handleScroll() => _scheduleVisibilityCheck();

  void _checkVisibility() {
    _settleTimer = null;
    if (!mounted || !_wantsUpgrade || !_isOnScreen()) return;
    final sharpUrl = widget.sharpUrl!;
    final load = widget.load;
    late final ChatImageUpgradeTicket ticket;
    ticket = _queue.schedule(() async {
      try {
        // 排队期间被滑出屏幕（还没销毁、在列表预加载区里）：轮到它也不下，让给别的；
        // 滑回来停稳后会重新排队。气泡销毁时票已经撤掉了。
        if (!mounted || !_isOnScreen()) return;
        final data = await load(sharpUrl);
        if (!mounted || widget.sharpUrl != sharpUrl) return;
        setState(() {
          _sharp = data;
          _fadeDone = _base == null;
        });
      } catch (_) {
        if (mounted && widget.sharpUrl == sharpUrl) {
          setState(() => _sharpFailed = true);
        }
      } finally {
        if (identical(_ticket, ticket)) _ticket = null;
      }
    });
    _ticket = ticket;
  }

  void _cancelUpgrade() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _ticket?.cancel();
    _ticket = null;
  }

  /// 气泡和它所在的滚动区域（没有就是整个窗口）有没有重叠。被别的页面盖住（TickerMode 关了）不算。
  bool _isOnScreen() {
    if (!TickerMode.valuesOf(context).enabled) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    Rect? viewport;
    final scrollBox = _scrollable?.context.findRenderObject();
    if (scrollBox is RenderBox && scrollBox.attached && scrollBox.hasSize) {
      viewport = MatrixUtils.transformRect(
        scrollBox.getTransformTo(null),
        Offset.zero & scrollBox.size,
      );
    } else {
      final size = MediaQuery.maybeSizeOf(context);
      if (size != null) viewport = Offset.zero & size;
    }
    if (viewport == null) return true;
    final overlap = rect.intersect(viewport);
    return overlap.width > 0 && overlap.height > 0;
  }

  @override
  Widget build(BuildContext context) {
    final sharp = _sharp;
    final base = _base;
    final layout = sharp ?? base;
    if (layout == null) {
      return _baseFailed
          ? widget.errorBuilder(context)
          : widget.placeholder(context);
    }
    final Widget image;
    if (sharp == null) {
      image = _thumbnailImage(base!);
    } else if (_fadeDone || base == null) {
      image = _sharpImage(sharp, fade: false);
    } else {
      image = Stack(
        fit: StackFit.expand,
        children: [
          _thumbnailImage(base),
          _sharpImage(sharp, fade: true),
        ],
      );
    }
    return widget.builder(context, layout, image);
  }

  /// 缩略图在气泡里是放大显示的：用 high（双三次）插值，比默认的双线性柔和不起块。
  Widget _thumbnailImage(ChatImageData data) => Image.memory(
        data.bytes,
        key: const ValueKey('chat-image-thumbnail'),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) => widget.errorBuilder(context),
      );

  /// 清晰图比气泡大，是缩小显示的：medium（带 mipmap）缩小最干净。
  /// 解码出第一帧才淡入（没解完之前下面还是缩略图），缓存里现成的直接显示。
  Widget _sharpImage(ChatImageData data, {required bool fade}) {
    final base = _base;
    return Image.memory(
      data.bytes,
      key: const ValueKey('chat-image-sharp'),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, _, __) => base == null
          ? widget.errorBuilder(context)
          : _thumbnailImage(base),
      frameBuilder: !fade
          ? null
          : (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _endFade());
                return child;
              }
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                onEnd: frame == null ? null : _endFade,
                child: child,
              );
            },
    );
  }

  void _endFade() {
    if (mounted && _sharp != null && !_fadeDone) {
      setState(() => _fadeDone = true);
    }
  }
}
