import 'package:chat_app/services/slash_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final commands = buildSlashCommands(
    agentLabel: 'Agent',
    bots: const [
      SlashBotEntry(label: '画画小助手', botName: 'painter'),
      SlashBotEntry(label: 'Deploy Bot', botName: 'deployer'),
      // 和内置命令重名的机器人不能抢走 /画图。
      SlashBotEntry(label: '画图', botName: 'fake-draw'),
    ],
  );

  List<String> names(Iterable<SlashCommand> list) =>
      [for (final command in list) command.name];

  group('slashCommandQuery', () {
    test(
        'only while the message starts with / and the cursor is inside the name',
        () {
      expect(slashCommandQuery('/', 1), '');
      expect(slashCommandQuery('/画', 2), '画');
      expect(slashCommandQuery('/画图 猫', 5), isNull);
      expect(slashCommandQuery('你好 /画', 4), isNull);
      expect(slashCommandQuery(' /画', 3), isNull);
      expect(slashCommandQuery('/画图', 0), isNull);
      expect(slashCommandQuery('', 0), isNull);
    });
  });

  group('buildSlashCommands', () {
    test(
        'built-ins first, then bots, then tools; duplicates of built-ins dropped',
        () {
      expect(names(commands), ['画图', '问', '画画小助手', 'Deploy Bot', '投票', '位置']);
      expect(
          commands.where((c) => c.kind == SlashCommandKind.bot), hasLength(2));
    });

    test('no /问 without a system agent', () {
      expect(names(buildSlashCommands()), ['画图', '投票', '位置']);
    });
  });

  group('filterSlashCommands', () {
    test('matches name, send names and aliases by prefix, case-insensitively',
        () {
      expect(names(filterSlashCommands(commands, '')), names(commands));
      expect(names(filterSlashCommands(commands, '画')), ['画图', '画画小助手']);
      expect(names(filterSlashCommands(commands, 'DR')), ['画图']);
      expect(names(filterSlashCommands(commands, 'huatu')), ['画图']);
      expect(names(filterSlashCommands(commands, 'a')), ['问']);
      expect(names(filterSlashCommands(commands, 'wen')), ['问']);
      expect(names(filterSlashCommands(commands, 'poll')), ['投票']);
      expect(names(filterSlashCommands(commands, 'toupiao')), ['投票']);
      expect(names(filterSlashCommands(commands, 'weizhi')), ['位置']);
      expect(names(filterSlashCommands(commands, 'paint')), ['画画小助手']);
      expect(names(filterSlashCommands(commands, 'deploy')), ['Deploy Bot']);
      expect(filterSlashCommands(commands, 'chat'), isEmpty);
    });
  });

  group('parseSlashInvocation', () {
    test('draw with its aliases', () {
      for (final text in [
        '/画图 一只猫',
        '/draw 一只猫',
        '/IMG 一只猫',
        '  /画图   一只猫  '
      ]) {
        final parsed = parseSlashInvocation(text, commands);
        expect(parsed?.command.kind, SlashCommandKind.draw, reason: text);
        expect(parsed?.body, '一只猫', reason: text);
      }
      expect(parseSlashInvocation('/画图', commands)?.body, '');
      // 拼音别名只用于面板筛选，直接发送不认。
      expect(parseSlashInvocation('/huatu 猫', commands), isNull);
      expect(parseSlashInvocation('/drawing 猫', commands), isNull);
      expect(parseSlashInvocation('/画图猫', commands), isNull);
    });

    test('ask and bots are rewritten to mentions', () {
      expect(parseSlashInvocation('/问 今天天气', commands)?.mentionText,
          '@Agent 今天天气');
      expect(parseSlashInvocation('/ask 今天天气', commands)?.mentionText,
          '@Agent 今天天气');
      expect(parseSlashInvocation('/画画小助手 画只狗', commands)?.mentionText,
          '@画画小助手 画只狗');
      expect(parseSlashInvocation('/deploy bot 上线', commands)?.mentionText,
          '@Deploy Bot 上线');
      expect(parseSlashInvocation('/deployer 上线', commands)?.mentionText,
          '@Deploy Bot 上线');
    });

    test('the longest name wins', () {
      final similar = buildSlashCommands(
        agentLabel: 'Agent',
        bots: const [
          SlashBotEntry(label: 'Deploy', botName: 'x'),
          SlashBotEntry(label: 'Deploy Bot', botName: 'y'),
        ],
      );
      expect(parseSlashInvocation('/Deploy Bot now', similar)?.mentionText,
          '@Deploy Bot now');
      expect(parseSlashInvocation('/Deploy now', similar)?.mentionText,
          '@Deploy now');
    });

    test('unknown commands and ordinary text are left alone', () {
      expect(parseSlashInvocation('/chat 你好', commands), isNull);
      expect(parseSlashInvocation('你好 /画图 猫', commands), isNull);
      expect(parseSlashInvocation('/', commands), isNull);
      expect(parseSlashInvocation('/问 x', buildSlashCommands()), isNull);
    });

    test('tools', () {
      expect(parseSlashInvocation('/投票', commands)?.command.kind,
          SlashCommandKind.poll);
      expect(parseSlashInvocation('/location', commands)?.command.kind,
          SlashCommandKind.location);
    });
  });

  test('isDrawCommandInProgress', () {
    expect(isDrawCommandInProgress('/画图 ', commands), isTrue);
    expect(isDrawCommandInProgress('/draw a cat', commands), isTrue);
    expect(isDrawCommandInProgress('/画图', commands), isFalse);
    expect(isDrawCommandInProgress('/问 x', commands), isFalse);
    expect(isDrawCommandInProgress('画图 x', commands), isFalse);
  });

  test('AI commands are flagged', () {
    final byKind = {for (final c in commands) c.kind: c.usesAi};
    expect(byKind[SlashCommandKind.draw], isTrue);
    expect(byKind[SlashCommandKind.ask], isTrue);
    expect(byKind[SlashCommandKind.bot], isTrue);
    expect(byKind[SlashCommandKind.poll], isFalse);
    expect(byKind[SlashCommandKind.location], isFalse);
  });
}
