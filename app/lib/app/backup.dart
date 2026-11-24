// 备份格式：单文件 .ragchat.zip，内含一份 data.json。
//
// 只导出「内容」：会话、轮次、记忆、人设与外观设置。
// 不导出：API key（Keychain）、模型路径、模型文件、用量账本。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../chat/app_db.dart';
import 'persona.dart';
import 'settings.dart';

const backupFormat = 'ragchat-backup';
const backupVersion = 1;

/// 备份里包含的设置项（白名单，避免把敏感或设备相关字段带出去）。
const _settingKeys = [
  'personasJson',
  'activePersonaId',
  'temperature',
  'ttsAutoRead',
  'ttsRate',
  'ttsPitch',
  'backend',
  'cloudBaseUrl',
  'cloudModel',
];

class BackupPreview {
  BackupPreview({
    required this.sessions,
    required this.turns,
    required this.memories,
    required this.exportedAt,
    required this.appVersion,
  });

  final int sessions;
  final int turns;
  final int memories;
  final String? exportedAt;
  final String? appVersion;

  String get summary =>
      '$sessions 个会话 · $turns 轮对话 · $memories 条记忆';
}

/// 打一个备份包。
Future<Uint8List> buildBackup({
  required AppDb db,
  required AppSettings settings,
  required String appVersion,
}) async {
  final sessions = await db.dumpSessions();
  final memories = (await db.allMemories())
      .map(
        (m) => {
          'id': m.id,
          'content': m.content,
          'kind': m.kind.name,
          'importance': m.importance,
          'createdAt': m.createdAt.millisecondsSinceEpoch,
          'updatedAt': m.updatedAt.millisecondsSinceEpoch,
          'lastUsedAt': m.lastUsedAt?.millisecondsSinceEpoch,
          'source': m.source,
          'active': m.active,
        },
      )
      .toList();

  final settingsJson = {
    'personasJson': settings.personasJson,
    'activePersonaId': settings.activePersonaId,
    'temperature': settings.temperature,
    'ttsAutoRead': settings.ttsAutoRead,
    'ttsRate': settings.ttsRate,
    'ttsPitch': settings.ttsPitch,
    'backend': settings.backend,
    'cloudBaseUrl': settings.cloudBaseUrl,
    'cloudModel': settings.cloudModel,
  };

  final data = {
    'manifest': {
      'format': backupFormat,
      'version': backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': appVersion,
    },
    'sessions': sessions,
    'memories': memories,
    'settings': settingsJson,
  };

  final readme = '''
RAGchat 备份

- 解开后 data.json 里有会话、记忆与人设设置。
- 不含 API key、模型文件与模型路径。
- 在 App 里用「导入备份」恢复；导入会覆盖当前会话与记忆。
''';

  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'data.json',
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)).length,
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      ),
    )
    ..addFile(
      ArchiveFile('README.txt', utf8.encode(readme).length, utf8.encode(readme)),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// 解包并校验，不落库。
BackupPreview inspectBackup(Uint8List bytes) {
  final data = _readData(bytes);
  final sessions = (data['sessions'] as List?) ?? const [];
  var turns = 0;
  for (final s in sessions) {
    turns += ((s as Map)['turns'] as List?)?.length ?? 0;
  }
  final memories = (data['memories'] as List?) ?? const [];
  final manifest = (data['manifest'] as Map?) ?? const {};
  return BackupPreview(
    sessions: sessions.length,
    turns: turns,
    memories: memories.length,
    exportedAt: manifest['exportedAt'] as String?,
    appVersion: manifest['appVersion'] as String?,
  );
}

/// 导入：整库替换会话与记忆，并把白名单设置写回。
/// [settings] 会被就地修改，调用方负责 save。
Future<BackupPreview> applyBackup({
  required Uint8List bytes,
  required AppDb db,
  required AppSettings settings,
}) async {
  final data = _readData(bytes);
  final sessions = ((data['sessions'] as List?) ?? const [])
      .map((e) => Map<String, Object?>.from(e as Map))
      .toList();
  final memories = <MemoryEntry>[
    for (final raw in (data['memories'] as List?) ?? const [])
      _memoryFromJson(Map<String, dynamic>.from(raw as Map)),
  ];

  final preview = inspectBackup(bytes);
  await db.restoreAll(sessions: sessions, memories: memories);

  final s = (data['settings'] as Map?) ?? const {};
  for (final key in _settingKeys) {
    if (!s.containsKey(key)) continue;
    final v = s[key];
    switch (key) {
      case 'personasJson':
        if (v is String) settings.personasJson = v;
      case 'activePersonaId':
        if (v is String) settings.activePersonaId = v;
      case 'temperature':
        if (v is num) settings.temperature = v.toDouble();
      case 'ttsAutoRead':
        if (v is bool) settings.ttsAutoRead = v;
      case 'ttsRate':
        if (v is num) settings.ttsRate = v.toDouble();
      case 'ttsPitch':
        if (v is num) settings.ttsPitch = v.toDouble();
      case 'backend':
        if (v == 'local' || v == 'cloud') settings.backend = v as String;
      case 'cloudBaseUrl':
        if (v is String) settings.cloudBaseUrl = v;
      case 'cloudModel':
        if (v is String) settings.cloudModel = v;
    }
  }
  // 人设列表至少要能解出两张卡，否则回退默认。
  if (settings.personas().isEmpty) {
    settings.personasJson = PersonaCard.encodeList(defaultPersonaSlots());
  }
  return preview;
}

MemoryEntry _memoryFromJson(Map<String, dynamic> j) {
  DateTime ts(Object? v, DateTime fallback) => v is num
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
      : fallback;
  final now = DateTime.now();
  return MemoryEntry(
    id: (j['id'] as String?) ?? 'm-${now.microsecondsSinceEpoch}',
    content: (j['content'] as String?) ?? '',
    kind: MemoryKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => MemoryKind.fact,
    ),
    importance: (j['importance'] as num?)?.toInt() ?? 3,
    createdAt: ts(j['createdAt'], now),
    updatedAt: ts(j['updatedAt'], now),
    lastUsedAt: j['lastUsedAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch((j['lastUsedAt'] as num).toInt())
        : null,
    source: j['source'] as String?,
    active: (j['active'] as bool?) ?? true,
  );
}

Map<String, dynamic> _readData(Uint8List bytes) {
  late final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('不是有效的备份文件（解压失败）');
  }
  final file = archive.files.where((f) => f.name == 'data.json').firstOrNull;
  if (file == null) throw const FormatException('备份里缺少 data.json');
  final map = jsonDecode(utf8.decode(file.content as List<int>));
  if (map is! Map<String, dynamic>) {
    throw const FormatException('备份内容格式不对');
  }
  final manifest = map['manifest'];
  if (manifest is! Map || manifest['format'] != backupFormat) {
    throw const FormatException('这不是 RAGchat 的备份文件');
  }
  final version = (manifest['version'] as num?)?.toInt() ?? 0;
  if (version > backupVersion) {
    throw const FormatException('备份来自更新的版本，请先升级 App');
  }
  return map;
}
