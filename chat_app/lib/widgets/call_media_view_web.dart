import 'package:flutter/material.dart';

class CallMediaView extends StatelessWidget {
  const CallMediaView({
    super.key,
    required this.viewId,
    required this.label,
  });

  final String? viewId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final id = viewId;
    if (id == null || id.isEmpty) {
      return _CallMediaPlaceholder(label: label);
    }
    return HtmlElementView(viewType: id);
  }
}

class _CallMediaPlaceholder extends StatelessWidget {
  const _CallMediaPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFF0F172A),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
