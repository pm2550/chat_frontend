import 'package:flutter/material.dart';

/// Compatibility layer for QQ's `[face:<id>]` message protocol.
///
/// Kirara emits these as standalone messages and QQ renders them as emoji
/// elements. Keeping the original message content unchanged makes old history
/// and future bot replies render the same way without a data migration.
class QqFace {
  const QqFace({
    required this.id,
    required this.label,
    this.assetPath,
  });

  final int id;
  final String label;
  final String? assetPath;

  bool get isBundled => assetPath != null;
}

class QqFaceCatalog {
  QqFaceCatalog._();

  static final RegExp _wholeFaceToken = RegExp(r'^\s*\[face:(\d+)\]\s*$');

  static const Map<int, QqFace> _bundledFaces = {
    11: QqFace(
      id: 11,
      label: '发怒',
      assetPath: 'assets/images/qq_faces/face_11.png',
    ),
    324: QqFace(
      id: 324,
      label: '吃糖',
      assetPath: 'assets/images/qq_faces/face_324.png',
    ),
  };

  /// Returns a face only for a standalone QQ token. Mixed prose remains text,
  /// matching Kirara's rule that expression messages are sent separately.
  static QqFace? parseStandalone(String content) {
    final match = _wholeFaceToken.firstMatch(content);
    if (match == null) return null;

    final id = int.tryParse(match.group(1)!);
    if (id == null) return null;
    return _bundledFaces[id] ?? QqFace(id: id, label: 'QQ 表情 #$id');
  }
}

class QqFaceMessage extends StatelessWidget {
  const QqFaceMessage({
    super.key,
    required this.face,
  });

  final QqFace face;

  @override
  Widget build(BuildContext context) {
    if (!face.isBundled) {
      return Semantics(
        label: face.label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8E1EC)),
          ),
          child: Text(
            face.label,
            style: const TextStyle(
              color: Color(0xFF51627A),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'QQ 表情：${face.label}',
      image: true,
      child: Image.asset(
        face.assetPath!,
        width: 92,
        height: 92,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
