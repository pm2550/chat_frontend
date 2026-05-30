import 'package:chat_app/services/call_ice_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallIceConfig', () {
    test('parses authenticated TURN config from API response', () {
      final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final config = CallIceConfig.fromApiResponse({
        'code': 200,
        'data': {
          'ttl': 1800,
          'expiresAt': 1800,
          'iceServers': [
            {
              'urls': ['stun:192.9.134.169:3478'],
            },
            {
              'urls': [
                'turn:192.9.134.169:3478?transport=udp',
                'turn:192.9.134.169:3478?transport=tcp',
              ],
              'username': '1800:user-7',
              'credential': 'signed',
            },
          ],
        },
      }, now: now);

      expect(config.ttlSeconds, 1800);
      expect(config.expiresAt,
          DateTime.fromMillisecondsSinceEpoch(1800000, isUtc: true));
      expect(config.iceServers, hasLength(2));
      expect(config.iceServers.last.username, '1800:user-7');
      expect(config.iceServers.last.credential, 'signed');
    });

    test('builds RTCPeerConnection policy with direct-first TURN fallback', () {
      final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final config = CallIceConfig.fromApiResponse({
        'iceServers': [
          {
            'urls': ['stun:192.9.134.169:3478'],
          },
        ],
        'ttl': 1800,
      }, now: now);

      final rtcConfig = config.toRtcConfigurationJson();

      expect(rtcConfig['iceTransportPolicy'], 'all');
      expect(rtcConfig['bundlePolicy'], 'max-bundle');
      expect(rtcConfig['rtcpMuxPolicy'], 'require');
      expect(config.canReuse(now.add(const Duration(minutes: 20))), isTrue);
      expect(config.canReuse(now.add(const Duration(minutes: 26))), isFalse);
      expect(config.shouldRefreshSoon(now.add(const Duration(minutes: 29))),
          isFalse);
      expect(
          config.shouldRefreshSoon(
              now.add(const Duration(minutes: 29, seconds: 5))),
          isTrue);
    });

    test('falls back to public STUN only when endpoint fails', () {
      final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final config = CallIceConfig.fallback(now: now);

      expect(config.fromFallback, isTrue);
      expect(
          config.iceServers.single.urls.single, 'stun:stun.l.google.com:19302');
      expect(
        config.toRtcConfigurationJson()['iceTransportPolicy'],
        'all',
      );
    });
  });
}
