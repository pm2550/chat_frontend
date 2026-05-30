import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  final String? userName;
  final List<String> userNames;
  final bool isBot;

  const TypingIndicator({
    super.key,
    this.userName,
    this.userNames = const [],
    this.isBot = false,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(reverse: true);
    });

    // Stagger the animations
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) _controllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isBot)
            const Icon(Icons.smart_toy, size: 14, color: Colors.blue),
          if (!widget.isBot)
            const Icon(Icons.edit, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            _typingLabel(),
            style: TextStyle(
              fontSize: 12,
              color: widget.isBot ? Colors.blue : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controllers[index],
              builder: (_, __) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  child: Opacity(
                    opacity: 0.3 + 0.7 * _controllers[index].value,
                    child: Text(
                      '.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: widget.isBot ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  String _typingLabel() {
    final names = widget.userNames.isNotEmpty
        ? widget.userNames
        : [
            if (widget.userName != null && widget.userName!.isNotEmpty)
              widget.userName!,
          ];
    if (names.isEmpty) return '正在输入';
    if (names.length == 1) return '${names.first} 正在输入';
    if (names.length <= 3) return '${names.join('、')} 正在输入';
    return '${names.length} 人正在输入';
  }
}
