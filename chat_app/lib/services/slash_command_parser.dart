/// 输入框里的 "/" 快捷命令：像 AI agent app 那样，输入 / 弹出命令面板，
/// 或者直接打 "/画图 一只猫" 回车。这里只有纯逻辑（命令表、前缀过滤、发送时解析），
/// 界面和真正执行在 screens/chat/sub/slash_commands.dart。
library;

enum SlashCommandKind {
  /// AI 画图：发送时走图片生成，不发文字。
  draw,

  /// 问内置 AI 助手：改写成 "@助手 问题" 发出去。
  ask,

  /// 房间里的某个机器人：改写成 "@机器人 内容"。
  bot,

  /// 打开投票面板。
  poll,

  /// 打开发送位置。
  location,
}

class SlashCommand {
  const SlashCommand({
    required this.kind,
    required this.name,
    required this.description,
    this.sendNames = const [],
    this.aliases = const [],
    this.mentionLabel,
    this.avatarUrl,
  });

  final SlashCommandKind kind;

  /// 面板里显示的名字（不带 /），也是选中后/直接输入时认的主名字。
  final String name;
  final String description;

  /// 除 [name] 外，直接输入 "/xxx 内容" 发送时也认的名字（如 draw、ask）。
  final List<String> sendNames;

  /// 只用来在面板里筛选的别名（拼音等），直接发送时不认，免得误伤普通消息。
  final List<String> aliases;

  /// [SlashCommandKind.ask] / [SlashCommandKind.bot]：要 @ 的名字。
  final String? mentionLabel;
  final String? avatarUrl;

  /// 画图、问 AI、机器人：内容都要交给服务器上的 AI，端到端加密的私聊里不能用。
  bool get usesAi =>
      kind == SlashCommandKind.draw ||
      kind == SlashCommandKind.ask ||
      kind == SlashCommandKind.bot;

  Iterable<String> get _allSendNames sync* {
    yield name;
    yield* sendNames;
  }

  /// 面板筛选：命令名、发送名、别名任一以 [query] 开头（不分大小写）。
  bool matchesPrefix(String query) {
    final needle = query.toLowerCase();
    if (needle.isEmpty) return true;
    return [..._allSendNames, ...aliases]
        .any((candidate) => candidate.toLowerCase().startsWith(needle));
  }
}

/// 一个能在面板里 @ 的机器人（内置 AI 助手之外的）。
class SlashBotEntry {
  const SlashBotEntry({
    required this.label,
    required this.botName,
    this.avatarUrl,
  });

  /// 群里 @ 它用的名字（群昵称或机器人名）。
  final String label;
  final String botName;
  final String? avatarUrl;
}

const String kSlashDrawDescription = 'AI 画图 · 每天免费 3 次，之后每次 10 积分';
const String kSlashAskDescription = '问 AI 助手（能联网搜索、看本群记录）';
const String kSlashBotDescription = '召唤机器人';

/// 当前房间能用的命令，按面板里的顺序。没有内置助手就没有 /问；
/// 机器人名字和内置命令重名时，内置命令优先。
List<SlashCommand> buildSlashCommands({
  String? agentLabel,
  List<SlashBotEntry> bots = const [],
}) {
  final commands = <SlashCommand>[
    const SlashCommand(
      kind: SlashCommandKind.draw,
      name: '画图',
      description: kSlashDrawDescription,
      sendNames: ['draw', 'img'],
      aliases: ['huatu'],
    ),
    if (agentLabel != null && agentLabel.trim().isNotEmpty)
      SlashCommand(
        kind: SlashCommandKind.ask,
        name: '问',
        description: kSlashAskDescription,
        sendNames: const ['ask'],
        aliases: const ['ai', 'wen'],
        mentionLabel: agentLabel.trim(),
      ),
  ];
  final taken = <String>{
    for (final command in commands) ...command._allSendNames.map(_fold),
    ..._builtinToolNames.map(_fold),
  };
  for (final bot in bots) {
    final label = bot.label.trim();
    if (label.isEmpty || !taken.add(_fold(label))) continue;
    final botName = bot.botName.trim();
    final extra = botName.isNotEmpty && taken.add(_fold(botName));
    commands.add(SlashCommand(
      kind: SlashCommandKind.bot,
      name: label,
      description: kSlashBotDescription,
      sendNames: extra ? [botName] : const [],
      mentionLabel: label,
      avatarUrl: bot.avatarUrl,
    ));
  }
  commands.addAll(const [
    SlashCommand(
      kind: SlashCommandKind.poll,
      name: '投票',
      description: '创建问题和选项，让大家投票',
      sendNames: ['poll'],
      aliases: ['toupiao'],
    ),
    SlashCommand(
      kind: SlashCommandKind.location,
      name: '位置',
      description: '发送一个地点或地图链接',
      sendNames: ['location'],
      aliases: ['weizhi'],
    ),
  ]);
  return commands;
}

const _builtinToolNames = ['投票', 'poll', '位置', 'location'];

String _fold(String value) => value.toLowerCase();

/// 光标前的文字是不是正在输入的命令：整条消息以 "/" 开头，"/" 到光标之间没有空白。
/// 是就返回 "/" 后面已经打的部分（可能为空），否则返回 null。
String? slashCommandQuery(String text, int cursor) {
  if (cursor < 1 || cursor > text.length || !text.startsWith('/')) {
    return null;
  }
  final query = text.substring(1, cursor);
  if (query.contains(RegExp(r'\s'))) return null;
  return query;
}

/// 面板要显示的命令：按前缀过滤，保持原顺序。
List<SlashCommand> filterSlashCommands(
  List<SlashCommand> commands,
  String query,
) =>
    commands.where((command) => command.matchesPrefix(query)).toList();

/// 发送时识别出的命令和它后面的内容（已去掉首尾空白，可能为空）。
class SlashInvocation {
  const SlashInvocation(this.command, this.body);

  final SlashCommand command;
  final String body;

  /// ask / bot 改写后真正发出去的文字。
  String get mentionText => '@${command.mentionLabel} $body';
}

/// 整条消息（已 trim）是 "/命令" 或 "/命令 内容" 时返回对应命令，否则 null——
/// 不认识的 "/xxx"（例如机器人的关键词 "/chat 你好"）原样当普通文字发。
/// 名字较长的先匹配，避免 "/画图" 被名叫 "画" 的机器人抢走。
SlashInvocation? parseSlashInvocation(
  String text,
  List<SlashCommand> commands,
) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('/')) return null;
  final rest = trimmed.substring(1);
  final candidates = <(String, SlashCommand)>[
    for (final command in commands)
      for (final name in command._allSendNames)
        if (name.isNotEmpty) (name, command),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  for (final (name, command) in candidates) {
    if (rest.length < name.length ||
        _fold(rest.substring(0, name.length)) != _fold(name)) {
      continue;
    }
    final after = rest.substring(name.length);
    if (after.isNotEmpty && !after.startsWith(RegExp(r'\s'))) continue;
    return SlashInvocation(command, after.trim());
  }
  return null;
}

/// 输入框里现在是不是一条画图命令（"/画图 " 后面正在写描述），用来显示画图提示。
bool isDrawCommandInProgress(String text, List<SlashCommand> commands) {
  final trimmedStart = text.trimLeft();
  if (!RegExp(r'^/\S+\s').hasMatch(trimmedStart)) return false;
  return parseSlashInvocation(trimmedStart, commands)?.command.kind ==
      SlashCommandKind.draw;
}
