import '../constants/api_constants.dart';

/// 加好友二维码的内容格式。
///
/// 二维码里放的是网页深链接 `https://<网页版地址>/#/add/<用户名>`：
/// 用 App 扫能直接识别；用系统相机或微信扫会打开网页版并进入同一个加好友页。
/// 用户名在系统里唯一且稳定，比数据库 ID 更适合长期印在二维码上。
class FriendCode {
  FriendCode._();

  static const String routePrefix = '/add/';

  // 注册只限制了用户名长度（3-50），不限制字符，所以这里只排除空白和
  // 会破坏路由的 / ? #。
  static final RegExp _usernamePattern = RegExp(r'^[^\s/?#]{1,64}$');
  static final RegExp _addPath = RegExp(r'^/?add/([^/?#]+)/?$');

  /// 应用内路由，例如 `/add/alice`。
  static String routeFor(String username) =>
      '$routePrefix${Uri.encodeComponent(username)}';

  /// 二维码 / 分享用的完整链接。
  static String linkFor(String username) {
    var base = ApiConstants.webAppUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/#${routeFor(username)}';
  }

  /// 从扫码结果或手动输入里解析出要精确查找的目标；认不出来返回 null。
  ///
  /// - 我们的加好友链接 / `/add/<用户名>` 路由 → 用户名
  /// - 纯用户名（可带前导 @）→ 用户名；全数字时同时作为用户 ID 备选
  /// - 其它网址或带空格的文本 → null（绝不拿去做模糊搜索）
  static FriendCodeTarget? parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final fromFragment = _usernameFromRoute(uri.fragment);
      if (fromFragment != null) return FriendCodeTarget(username: fromFragment);
      final fromPath = _usernameFromRoute(uri.path);
      if (fromPath != null) return FriendCodeTarget(username: fromPath);
      return null;
    }

    final fromRoute = _usernameFromRoute(value);
    if (fromRoute != null) return FriendCodeTarget(username: fromRoute);

    final plain = value.startsWith('@') ? value.substring(1) : value;
    if (!_usernamePattern.hasMatch(plain)) return null;
    final isNumeric = RegExp(r'^\d+$').hasMatch(plain);
    return FriendCodeTarget(username: plain, id: isNumeric ? plain : null);
  }

  /// 从路由名里取用户名（`/add/alice` → alice），不是加好友路由返回 null。
  static String? usernameFromRoute(String? routeName) =>
      routeName == null ? null : _usernameFromRoute(routeName);

  static String? _usernameFromRoute(String route) {
    final match = _addPath.firstMatch(route.split('?').first);
    if (match == null) return null;
    final String decoded;
    try {
      decoded = Uri.decodeComponent(match.group(1)!).trim();
    } on ArgumentError {
      return null;
    }
    return _usernamePattern.hasMatch(decoded) ? decoded : null;
  }
}

class FriendCodeTarget {
  const FriendCodeTarget({this.username, this.id});

  /// 按用户名精确查找。
  final String? username;

  /// 用户名查不到时，再按用户 ID 精确查找（只在输入是纯数字时提供）。
  final String? id;
}
