class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    this.ownerUserId,
    this.isPublic = true,
    this.coverUrl,
  });

  final int id;
  final String name;
  final int? ownerUserId;
  final bool isPublic;
  final String? coverUrl;

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    return StickerPack(
      id: _intValue(json['id']),
      name: json['name']?.toString() ?? '贴纸包',
      ownerUserId: _intOrNull(json['ownerUserId']),
      isPublic: json['isPublic'] != false,
      coverUrl: _stringOrNull(json['coverUrl']),
    );
  }
}

class StickerItem {
  const StickerItem({
    required this.id,
    required this.packId,
    this.url,
    this.keyword,
    this.indexInPack = 0,
  });

  final int id;
  final int packId;
  final String? url;
  final String? keyword;
  final int indexInPack;

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    return StickerItem(
      id: _intValue(json['id']),
      packId: _intValue(json['packId']),
      url: _stringOrNull(json['url']),
      keyword: _stringOrNull(json['keyword']),
      indexInPack: _intValue(json['indexInPack']),
    );
  }
}

int _intValue(dynamic value) => _intOrNull(value) ?? 0;

int? _intOrNull(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

String? _stringOrNull(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
