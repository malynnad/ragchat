import 'dart:convert';

/// 人设卡（ADR-0009，2026-11-16 改为「单卡 + 自由正文」）。
///
/// 正文 [text] 是唯一的权威内容：非空就整段写进 system（借鉴
/// dsh-persona-dafeiyu 的整段 markdown 做法，可放标题、例子、口癖）。
/// 五要素字段只为兼容旧 settings.json 保留，正文为空时才拼成一句话。
class PersonaCard {
  const PersonaCard({
    required this.id,
    required this.name,
    this.text = '',
    this.personality = '',
    this.style = '',
    this.addressTerm = '',
    this.boundary = '',
  });

  final String id;
  final String name;

  /// 人设正文（markdown 随意）：非空 = 整段注入，替代五要素。
  final String text;

  /// 旧版五要素（仅为读旧数据保留）。
  final String personality;
  final String style;
  final String addressTerm;
  final String boundary;

  bool get isLegacy => text.trim().isEmpty;

  PersonaCard copyWith({
    String? name,
    String? text,
    String? personality,
    String? style,
    String? addressTerm,
    String? boundary,
  }) => PersonaCard(
    id: id,
    name: name ?? this.name,
    text: text ?? this.text,
    personality: personality ?? this.personality,
    style: style ?? this.style,
    addressTerm: addressTerm ?? this.addressTerm,
    boundary: boundary ?? this.boundary,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'text': text,
    // 五要素照旧落盘：旧版本 App 读回时不至于丢内容。
    'personality': personality,
    'style': style,
    'addressTerm': addressTerm,
    'boundary': boundary,
  };

  static PersonaCard fromJson(Map<String, dynamic> j) => PersonaCard(
    id: j['id'] as String,
    name: j['name'] as String? ?? '未命名',
    text: j['text'] as String? ?? '',
    personality: j['personality'] as String? ?? '',
    style: j['style'] as String? ?? '',
    addressTerm: j['addressTerm'] as String? ?? '',
    boundary: j['boundary'] as String? ?? '',
  );

  /// system 消息片段：正文优先，空正文回落五要素拼句（空卡返回空串）。
  String render() {
    final body = text.trim();
    if (body.isNotEmpty) return body;
    final parts = <String>[
      if (personality.isNotEmpty) '性格：$personality',
      if (style.isNotEmpty) '说话风格：$style',
      if (addressTerm.isNotEmpty) '称呼用户为「$addressTerm」',
      if (boundary.isNotEmpty) '边界：$boundary',
    ];
    if (parts.isEmpty) {
      return name.isEmpty ? '' : '你是$name。';
    }
    return '你是${name.isEmpty ? '聊天助手' : name}。${parts.join('。')}。';
  }

  /// 序列化到 settings.json 的 personas 列表。
  static String encodeList(List<PersonaCard> cards) =>
      jsonEncode([for (final c in cards) c.toJson()]);

  static List<PersonaCard> decodeList(String? json) {
    if (json == null || json.isEmpty) return List.of(builtinPersonas);
    try {
      final list = jsonDecode(json) as List;
      final cards = [
        for (final e in list) PersonaCard.fromJson(e as Map<String, dynamic>),
      ];
      return cards.isEmpty ? List.of(builtinPersonas) : cards;
    } catch (_) {
      return List.of(builtinPersonas);
    }
  }
}

/// 内置预设：写成短正文当「够短的样板」（手机端每轮都吃 system 预算）。
/// 用户可整段改掉、也可照着结构扩写。
const List<PersonaCard> builtinPersonas = [
  PersonaCard(
    id: 'assistant',
    name: '小助',
    text: '你是小助，一个干活的助手。\n\n'
        '- 语气平静自然，不寒暄、不卖萌。\n'
        '- 能一句说清就别铺开；有步骤就分点列。\n'
        '- 不确定就说不确定，缺信息就问，不编。',
  ),
  PersonaCard(
    id: 'companion',
    name: '小暖',
    text: '你是小暖，一个陪聊的朋友。\n\n'
        '- 语气温和、口语化，像熟人说话。\n'
        '- 回答短：一两句、十几二十个字，别写小作文。\n'
        '- 记得他说过的事，顺手带进对话里。\n'
        '- 不确定就说不确定，不编。',
  ),
  PersonaCard(
    id: 'tutor',
    name: '阿博',
    text: '你是阿博，负责把事讲明白的人。\n\n'
        '- 先给结论，再讲为什么。\n'
        '- 举生活里的例子，不堆术语。\n'
        '- 不确定的地方明说，不编造。',
  ),
];
