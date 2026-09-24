import 'package:url_launcher/url_launcher.dart';

/// 聊天正文里的链接识别与安全打开。
///
/// 用户消息只允许打开 http/https：`javascript:`、`file:`、`data:` 之类的
/// 链接一律当普通文本，既不高亮也不响应点击。
class LinkUtils {
  LinkUtils._();

  /// 一段正文里的网址。遇到空白、尖括号/括号/引号，或者中文字符与全角标点
  /// 就结束，避免“https://a.com看看”把后面的中文吞进链接。
  static final RegExp urlPattern = RegExp(
    r'https?://[^\s<>()\[\]{}"'
    "'"
    r'　-〿一-鿿＀-￯]+',
    caseSensitive: false,
  );

  static final RegExp _trailingPunctuation = RegExp(r'[.,;:!?]+$');

  /// 找出正文中所有可点击网址的位置（已去掉句末标点）。
  static List<LinkMatch> findUrls(String text) {
    final matches = <LinkMatch>[];
    for (final match in urlPattern.allMatches(text)) {
      final raw = match.group(0) ?? '';
      final trimmed = raw.replaceFirst(_trailingPunctuation, '');
      if (safeWebUri(trimmed) == null) continue;
      matches
          .add(LinkMatch(match.start, match.start + trimmed.length, trimmed));
    }
    return matches;
  }

  static String? firstUrl(String text) {
    final matches = findUrls(text);
    return matches.isEmpty ? null : matches.first.url;
  }

  /// 只有带主机名的 http/https 地址才返回 Uri，其余一律返回 null。
  static Uri? safeWebUri(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  static final RegExp _coordinatePattern = RegExp(
    r'(-?\d{1,2}(?:\.\d+)?)\s*[,，]\s*(-?\d{1,3}(?:\.\d+)?)',
  );

  /// 位置消息可以打开的地图地址：正文里有地图链接就用它；有“纬度,经度”
  /// 坐标就生成一个地图标记链接；只有地名时返回 null（没有可靠的地方可去）。
  static Uri? mapUriForLocation(String content) {
    final url = firstUrl(content);
    if (url != null) return safeWebUri(url);
    final match = _coordinatePattern.firstMatch(content);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return Uri.https('www.openstreetmap.org', '/', {
      'mlat': '$lat',
      'mlon': '$lng',
    }).replace(fragment: 'map=16/$lat/$lng');
  }

  /// 用系统浏览器打开 http/https 链接；不安全的链接直接忽略并返回 false。
  static Future<bool> openExternal(String? raw) async {
    final uri = safeWebUri(raw);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

class LinkMatch {
  const LinkMatch(this.start, this.end, this.url);

  final int start;
  final int end;
  final String url;
}
