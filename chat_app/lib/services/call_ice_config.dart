class CallIceConfig {
  const CallIceConfig({
    required this.iceServers,
    required this.ttlSeconds,
    required this.expiresAt,
    this.fromFallback = false,
  });

  static const int fallbackTtlSeconds = 300;
  static const String fallbackStunUrl = 'stun:stun.l.google.com:19302';

  final List<CallIceServer> iceServers;
  final int ttlSeconds;
  final DateTime expiresAt;
  final bool fromFallback;

  factory CallIceConfig.fromApiResponse(
    Object? decoded, {
    DateTime? now,
  }) {
    final payload = _unwrapPayload(decoded);
    if (payload is! Map) {
      throw const FormatException('ICE response payload is not an object');
    }

    final rawServers = payload['iceServers'];
    if (rawServers is! List) {
      throw const FormatException('ICE response does not include iceServers');
    }

    final servers = rawServers
        .whereType<Map>()
        .map(CallIceServer.fromJson)
        .where((server) => server.urls.isNotEmpty)
        .toList(growable: false);
    if (servers.isEmpty) {
      throw const FormatException('ICE response has no usable servers');
    }

    final currentTime = now ?? DateTime.now().toUtc();
    final ttl = _asInt(payload['ttl']) ?? fallbackTtlSeconds;
    final expiresAtSeconds = _asInt(payload['expiresAt']);
    final expiresAt = expiresAtSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(
            expiresAtSeconds * 1000,
            isUtc: true,
          )
        : currentTime.add(Duration(seconds: ttl));

    return CallIceConfig(
      iceServers: servers,
      ttlSeconds: ttl,
      expiresAt: expiresAt,
    );
  }

  factory CallIceConfig.fallback({DateTime? now}) {
    final currentTime = now ?? DateTime.now().toUtc();
    return CallIceConfig(
      iceServers: const [
        CallIceServer(urls: [fallbackStunUrl])
      ],
      ttlSeconds: fallbackTtlSeconds,
      expiresAt: currentTime.add(const Duration(seconds: fallbackTtlSeconds)),
      fromFallback: true,
    );
  }

  bool canReuse(DateTime now) =>
      now.toUtc().isBefore(expiresAt.subtract(const Duration(minutes: 5)));

  bool shouldRefreshSoon(DateTime now) =>
      now.toUtc().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  Map<String, Object?> toRtcConfigurationJson() {
    return {
      'iceServers': iceServers.map((server) => server.toJson()).toList(),
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };
  }

  static Object? _unwrapPayload(Object? decoded) {
    if (decoded is Map && decoded['data'] is Map) {
      return decoded['data'];
    }
    return decoded;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class CallIceServer {
  const CallIceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  final List<String> urls;
  final String? username;
  final String? credential;

  factory CallIceServer.fromJson(Map<dynamic, dynamic> json) {
    final rawUrls = json['urls'];
    final urls = rawUrls is List
        ? rawUrls
            .map((url) => url.toString().trim())
            .where((url) => url.isNotEmpty)
            .toList(growable: false)
        : [
            rawUrls?.toString().trim() ?? '',
          ].where((url) => url.isNotEmpty).toList(growable: false);

    final username = _nonEmpty(json['username']);
    final credential = _nonEmpty(json['credential']);
    return CallIceServer(
      urls: urls,
      username: username,
      credential: credential,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'urls': urls.length == 1 ? urls.first : urls,
      if (username != null && credential != null) 'username': username,
      if (username != null && credential != null) 'credential': credential,
    };
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
