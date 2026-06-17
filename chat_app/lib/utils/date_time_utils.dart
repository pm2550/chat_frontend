DateTime? parseServerDateTime(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return null;
  }
  final hasExplicitZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
  final normalized = hasExplicitZone ? text : '${text}Z';
  return DateTime.tryParse(normalized)?.toLocal();
}
