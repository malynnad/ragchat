import 'dart:convert';

/// 人设卡（ADR-0009、ADR-0011）：一张、短、有口癖。
///
/// 只写「像人」需要的那几样：性格、说话方式、常用话、称呼。
/// 每项几十字封顶——手机端小模型每轮都要重付这段 token，
/// 写得越长首字出得越慢，指令也越容易糊。
class PersonaCard {
  const PersonaCard({
    required this.id,
    required this.name,
    this.personality = '',
    this.style = '',
    this.catchphrase = '',
    this.addressTerm = '',
    this.boundary = '',
    this.text = '',
  });

  final String id;
  final String name;

  /// 性格：几条形容词 + 一句「他大概是这样的人」。
  final String personality;

  /// 说话方式：句子长短、语气、要不要列点。
  final String style;

  /// 常用话 / 口癖：一两个短句，最出「人味」的那部分。
  final String catchphrase;

  /// 对用户的称呼，空则不指定。
  final String addressTerm;

  /// 不做什么（可选）。
  final String boundary;

  /// 旧版自由正文：只用于读回 ADR-0010 那次改动存下的数据。
  final String text;

  PersonaCard copyWith({
    String? name,
    String? personality,
    String? style,
    String? catchphrase,
    String? addressTerm,
    String? boundary,
    String? text,
  }) => PersonaCard(
    id: id,
    name: name ?? this.name,
    personality: personality ?? this.personality,
    style: style ?? this.style,
    catchphrase: catchphrase ?? this.catchphrase,
    addressTerm: addressTerm ?? this.addressTerm,
    boundary: boundary ?? this.boundary,
    text: text ?? this.text,
  );

  /// 一项都没填（旧数据的自由正文也算有内容）。
  bool get isEmpty =>
      personality.isEmpty &&
      style.isEmpty &&
      catchphrase.isEmpty &&
      addressTerm.isEmpty &&
      boundary.isEmpty &&
      text.isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'personality': personality,
    'style': style,
    'catchphrase': catchphrase,
    'addressTerm': addressTerm,
    'boundary': boundary,
  };

  static PersonaCard fromJson(Map<String, dynamic> j) => PersonaCard(
    id: j['id'] as String,
    name: j['name'] as String? ?? '未命名',
    personality: j['personality'] as String? ?? '',
    style: j['style'] as String? ?? '',
    catchphrase: j['catchphrase'] as String? ?? '',
    addressTerm: j['addressTerm'] as String? ?? '',
    boundary: j['boundary'] as String? ?? '',
    text: j['text'] as String? ?? '',
  );

  /// system 消息片段：有内容的字段才渲染，一句到底不加标题。
  /// 旧数据只存了自由正文（ADR-0010）时，原样用那段。
  String render() {
    final parts = <String>[
      if (personality.isNotEmpty) '性格：$personality',
      if (style.isNotEmpty) '说话：$style',
      if (catchphrase.isNotEmpty) '常说：「$catchphrase」',
      if (addressTerm.isNotEmpty) '称呼用户为「$addressTerm」',
      if (boundary.isNotEmpty) '不做：$boundary',
    ];
    if (parts.isEmpty) {
      final legacy = text.trim();
      if (legacy.isNotEmpty) return legacy;
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

/// 内置三段：短，且带口癖——口癖比形容词更像人。
const List<PersonaCard> builtinPersonas = [
  PersonaCard(
    id: 'companion',
    name: '小暖',
    personality: '温和、爱笑，先接住情绪，不急着给建议',
    style: '口语，短句，一两句就停，不列点、不总结',
    catchphrase: '嗯，我在；那你慢慢说',
    addressTerm: '你',
  ),
  PersonaCard(
    id: 'assistant',
    name: '小助',
    personality: '干脆、务实，不说客套话',
    style: '先给结论，能一句就不写两句；要步骤才分点',
    catchphrase: '行；这就来',
    addressTerm: '你',
  ),
  PersonaCard(
    id: 'tutor',
    name: '阿博',
    personality: '耐心、爱打比方，把事讲明白为乐',
    style: '先结论再原因，多用生活里的例子，少术语',
    catchphrase: '这么说吧；比如',
    addressTerm: '你',
  ),
];
