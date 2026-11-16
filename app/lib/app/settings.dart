import 'dart:convert';
import 'dart:io';

import 'persona.dart';

/// 应用设置（ADR-0009）。JSON 持久化在 App 私有目录。
/// 新字段一律带默认值，旧 settings.json 向后兼容；RAG 时代字段
/// （refusalThreshold/topK/lastCategory/customPersona）读取容忍、写入丢弃。
class AppSettings {
  AppSettings({
    this.useGpu = false,
    this.confirmed = false,
    this.chatModelPath,
    this.embedModelPath,
    this.activePersonaId = 'dafeiyu',
    this.personasJson,
    this.accentId = 'blue',
  });

  /// ADR-0005：默认 CPU；GPU 仅作开关
  bool useGpu;

  /// 模型准备页是否已确认（US-1：首启必经准备页）
  bool confirmed;

  String? chatModelPath;

  /// 可选：MVP 嵌入模型非必需（US-24），仅 v2 情景记忆使用。
  String? embedModelPath;

  /// 当前激活的人设卡 id。
  String activePersonaId;

  /// 人设卡列表 JSON（PersonaCard.encodeList 产物）。
  /// null = 从未保存过，首次读取回退到内置预设。
  String? personasJson;

  /// 主题色档位 id：blue/purple/pink/orange/teal，默认蓝。
  String accentId;

  /// 当前人设卡（列表里找不到 activePersonaId 时回退第一张）。
  PersonaCard activePersona(List<PersonaCard> cards) => cards.firstWhere(
    (c) => c.id == activePersonaId,
    orElse: () => cards.first,
  );

  /// 人设卡列表：settings 里存的副本，缺失时内置预设兜底。
  List<PersonaCard> personas() => PersonaCard.decodeList(personasJson);

  static Future<AppSettings> load(String dirPath) async {
    final f = File('$dirPath/settings.json');
    if (!f.existsSync()) return AppSettings();
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return AppSettings(
        useGpu: j['useGpu'] as bool? ?? false,
        confirmed: j['confirmed'] as bool? ?? false,
        chatModelPath: j['chatModelPath'] as String?,
        embedModelPath: j['embedModelPath'] as String?,
        activePersonaId:
            j['activePersonaId'] as String? ??
            j['personaId'] as String? ?? // v2 旧字段名兼容
            'dafeiyu',
        personasJson: j['personasJson'] as String?,
        accentId: j['accentId'] as String? ?? 'blue',
      );
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save(String dirPath) async {
    await File('$dirPath/settings.json').writeAsString(
      jsonEncode({
        'useGpu': useGpu,
        'confirmed': confirmed,
        'chatModelPath': chatModelPath,
        'embedModelPath': embedModelPath,
        'activePersonaId': activePersonaId,
        'personasJson': personasJson ?? PersonaCard.encodeList(builtinPersonas),
        'accentId': accentId,
      }),
    );
  }
}
