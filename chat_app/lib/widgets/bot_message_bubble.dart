import 'package:flutter/material.dart';

class BotMessageBubble extends StatelessWidget {
  final String botName;
  final String content;
  final String? timestamp;

  const BotMessageBubble({
    super.key,
    required this.botName,
    required this.content,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blue[100],
            child: const Icon(Icons.smart_toy, size: 20, color: Colors.blue),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(botName, style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue,
                    )),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('BOT', style: TextStyle(
                        fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold,
                      )),
                    ),
                    if (timestamp != null) ...[
                      const Spacer(),
                      Text(timestamp!, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: SelectableText(content, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
