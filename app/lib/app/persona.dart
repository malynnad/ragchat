import 'dart:convert';

/// 人设卡（ADR-0009 决策 5，扩展 ADR-0007 的风格句）。
/// 五要素齐全但每项百字级——8B 以下模型指令遵循有限，越短越稳。
class PersonaCard {
  const PersonaCard({
    required this.id,
    required this.name,
    this.personality = '',
    this.style = '',
    this.addressTerm = '',
    this.boundary = '',
  });

  final String id;
  final String name;

  /// 性格描述：如「温柔耐心，喜欢倾听」。
  final String personality;

  /// 说话风格：如「口语化，短句，偶尔用表情符号」。
  final String style;

  /// 对用户的称呼：如「你」/「Danny」，空则不指定。
  final String addressTerm;

  /// 边界：如「不给医疗建议」，空则不指定。
  final String boundary;

  PersonaCard copyWith({
    String? name,
    String? personality,
    String? style,
    String? addressTerm,
    String? boundary,
  }) => PersonaCard(
    id: id,
    name: name ?? this.name,
    personality: personality ?? this.personality,
    style: style ?? this.style,
    addressTerm: addressTerm ?? this.addressTerm,
    boundary: boundary ?? this.boundary,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'personality': personality,
    'style': style,
    'addressTerm': addressTerm,
    'boundary': boundary,
  };

  static PersonaCard fromJson(Map<String, dynamic> j) => PersonaCard(
    id: j['id'] as String,
    name: j['name'] as String? ?? '未命名',
    personality: j['personality'] as String? ?? '',
    style: j['style'] as String? ?? '',
    addressTerm: j['addressTerm'] as String? ?? '',
    boundary: j['boundary'] as String? ?? '',
  );

  /// system 消息片段：有内容的字段才渲染（ADR-0007 教训：句越短越稳）。
  String render() {
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
      return [
        for (final e in list) PersonaCard.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return List.of(builtinPersonas);
    }
  }
}

/// 内置预设（用户可改可删，settings.json 里存全量副本）。
const List<PersonaCard> builtinPersonas = [
  PersonaCard(
    id: 'assistant',
    name: '小助',
    personality: '友好自然',
    style: '简洁清楚，不啰嗦',
  ),
  PersonaCard(
    id: 'companion',
    name: '小暖',
    personality: '温柔耐心，善于倾听',
    style: '口语化，带一点关心',
    addressTerm: '你',
  ),
  PersonaCard(
    id: 'tutor',
    name: '阿博',
    personality: '严谨博学',
    style: '条理分明，讲清为什么',
    boundary: '不确定时明说，不编造',
  ),
];
