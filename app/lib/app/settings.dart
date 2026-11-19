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
    this.activePersonaId = 'local',
    this.personasJson,
    this.accentId = 'blue',
    this.temperature = 0.6,
    this.skipModelSetup = false,
    this.backend = 'local',
    this.cloudBaseUrl = 'https://api.deepseek.com',
    this.cloudModel = 'deepseek-flash',
    this.ttsAutoRead = false,
    this.ttsRate = 0.5,
    this.ttsVoiceName,
    this.ttsVoiceLocale,
    this.ttsPitch = 1.0,
    this.ttsEngine,
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

  /// 采样温度：越低越稳（2B 模型高了容易语无伦次），默认 0.6。
  double temperature;

  /// 用户选择「稍后配置模型」：允许没有模型也进主界面。
  bool skipModelSetup;

  /// 对话后端：`local`（端上 GGUF）或 `cloud`（OpenAI 兼容 API）。
  String backend;

  /// 云端 baseURL；填到 /v1 也行，网关会自动补 /chat/completions。
  String cloudBaseUrl;

  /// 云端模型名：deepseek-flash（便宜快）或 deepseek-v4-pro（更强）。
  String cloudModel;

  /// 新回复自动朗读（系统 TTS，离线免费）。
  bool ttsAutoRead;

  /// 系统 TTS 语速：0.1–0.9，中文 0.5 左右接近正常说话。
  double ttsRate;

  /// 选中的系统音色（引擎里的 voice name + locale）；null = 引擎默认。
  String? ttsVoiceName;
  String? ttsVoiceLocale;

  /// 音调 0.7–1.3：0.85 偏低沉，1.15 偏清亮。部分引擎的音色其实同质，
  /// 这个是最直观的“换个声音”手段。
  double ttsPitch;

  /// 指定 TTS 引擎（Android 引擎包名）；null = 系统默认引擎。
  String? ttsEngine;

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
            'local',
        personasJson: j['personasJson'] as String?,
        accentId: j['accentId'] as String? ?? 'blue',
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.6,
        skipModelSetup: j['skipModelSetup'] as bool? ?? false,
        backend: j['backend'] as String? ?? 'local',
        cloudBaseUrl:
            j['cloudBaseUrl'] as String? ?? 'https://api.deepseek.com',
        cloudModel: j['cloudModel'] as String? ?? 'deepseek-flash',
        ttsAutoRead: j['ttsAutoRead'] as bool? ?? false,
        ttsRate: (j['ttsRate'] as num?)?.toDouble() ?? 0.5,
        ttsVoiceName: j['ttsVoiceName'] as String?,
        ttsVoiceLocale: j['ttsVoiceLocale'] as String?,
        ttsPitch: (j['ttsPitch'] as num?)?.toDouble() ?? 1.0,
        ttsEngine: j['ttsEngine'] as String?,
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
        'personasJson': personasJson ?? PersonaCard.encodeList(defaultPersonaSlots()),
        'accentId': accentId,
        'temperature': temperature,
        'skipModelSetup': skipModelSetup,
        'backend': backend,
        'cloudBaseUrl': cloudBaseUrl,
        'cloudModel': cloudModel,
        'ttsAutoRead': ttsAutoRead,
        'ttsRate': ttsRate,
        'ttsVoiceName': ttsVoiceName,
        'ttsVoiceLocale': ttsVoiceLocale,
        'ttsPitch': ttsPitch,
        'ttsEngine': ttsEngine,
      }),
    );
  }
}
