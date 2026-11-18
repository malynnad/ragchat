import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:nobodywho/nobodywho.dart' as nw;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../chat/app_db.dart';
import '../rag/model_catalog.dart';
import '../chat/chat_service.dart';
import '../chat/memory_service.dart';
import '../rag/models.dart';
import '../rag/cloud_gateway.dart';
import '../rag/nobodywho_gateway.dart';
import '../rag/secret_store.dart';
import '../rag/token_budget.dart';
import 'persona.dart';
import 'settings.dart';

class ModelFile {
  ModelFile(this.path, this.size);
  final String path;
  final int size;
  String get name => p.basename(path);
}

/// App 控制器：设置、模型准备、聊天会话、记忆管理的唯一状态源。
/// UI 经 AppStateScope 监听；ChatService 接缝保持可测试。
class AppState extends ChangeNotifier {
  AppSettings settings = AppSettings();
  String modelsDirPath = '';
  final modelFiles = <ModelFile>[];
  String loadStage = '';
  String? loadError;
  double? downloadProgress;
  String? downloadLabel;

  /// 正在下载的候选目录 URL（圆环进度）：供设置页定位"哪一行"显示圆环。
  /// 下载开始即置、结束清空；null 表示当前无下载。
  String? downloadingUrl;

  /// mac 外壳遗留的动作总线（保留接缝）：递增计数即触发一次新对话。
  final newConversationBus = ValueNotifier<int>(0);

  /// 主题模式（不持久化，重启回跟随系统）。
  ThemeMode themeMode = ThemeMode.system;
  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
  }

  String _supportDir = '';
  AppDb? _db;
  NobodyWhoGateway? _gateway;
  CloudGateway? _cloud;
  ChatService? _chatService;

  /// API key 走系统安全存储；测试可注入 MemorySecretStore。
  SecretStore secretStore = SecureSecretStore();
  String cloudApiKey = '';
  static const cloudKeyName = 'cloud_api_key';

  /// 云端上下文预算（DeepSeek 是 64K，留一点余量）。
  static const cloudContextSize = 64000;

  /// 当前会话（US-19 持久化）：重启恢复最近会话与轮次。
  String? currentSessionId;
  final sessionTurns = <SessionTurn>[];

  /// 记忆条目（US-21 记忆页数据源）：含停用，activeMemories 语义由调用方过滤。
  List<MemoryEntry> memories = [];

  /// US-1 下载源：hf-mirror（国内可达，已 HEAD 验证）；nobodywho 内置下载器。
  /// ADR-0009：陪聊默认 Qwen3.5-2B 速度档，优先低延迟与低内存占用。
  static const chatModelUrl =
      'https://www.modelscope.cn/models/unsloth/Qwen3.5-4B-GGUF/resolve/master/Qwen3.5-4B-Q4_K_M.gguf';

  /// 嵌入模型可选（MVP 不强制，US-24）；仅 v2 情景记忆需要。
  static const embedModelUrl =
      'https://hf-mirror.com/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf';

  bool get modelsReady =>
      settings.chatModelPath != null &&
      File(settings.chatModelPath!).existsSync();

  /// 首启必经模型准备页（US-1）；确认后直达主页。
  bool get entered =>
      settings.confirmed && (modelsReady || settings.skipModelSetup);

  bool get gatewayLoaded =>
      settings.backend == 'cloud' ? _chatService != null : _gateway?.loaded ?? false;

  Future<void> init() async {
    _supportDir = (await getApplicationSupportDirectory()).path;
    settings = await AppSettings.load(_supportDir);
    cloudApiKey = await secretStore.read(cloudKeyName) ?? '';
    await normalizePersonaSlots();
    _db = await AppDb.openFile(p.join(_supportDir, 'rag.db'));
    final ext = await getExternalStorageDirectory();
    modelsDirPath = p.join(ext!.path, 'models');
    await rescanModels();
    settings.chatModelPath ??= _autoAssignChat();
    await restoreLatestSession();
    await loadMemories();
    notifyListeners();
  }

  /// 文件名启发式预选生成角色：排除 embed 命名后的最大文件。
  String? _autoAssignChat() {
    return modelFiles
        .where((f) => !f.name.toLowerCase().contains('embed'))
        .fold<ModelFile?>(
          null,
          (big, f) => big == null || f.size > big.size ? f : big,
        )
        ?.path;
  }

  /// 重启恢复：最近会话 + 其轮次（US-19）。
  Future<void> restoreLatestSession() async {
    final db = _db!;
    final latest = await db.latestSession();
    if (latest == null) return;
    currentSessionId = latest.id;
    sessionTurns
      ..clear()
      ..addAll(await db.sessionTurns(latest.id));
  }

  // ---- 记忆（US-21）----

  Future<void> loadMemories() async {
    memories = await _db!.allMemories();
    notifyListeners();
  }

  /// active 记忆按注入序（importance 降序、同分按更新时间新者在前）。
  List<MemoryEntry> activeMemories() =>
      memories.where((m) => m.active).toList();

  Future<void> editMemory(MemoryEntry entry) async {
    await _db!.upsertMemory(entry);
    await loadMemories();
  }

  Future<void> deleteMemory(String id) async {
    await _db!.deleteMemory(id);
    await loadMemories();
  }

  Future<void> deactivateMemory(String id) async {
    await _db!.deactivateMemory(id);
    await loadMemories();
  }

  /// 手动提取（记忆页按钮）：对当前会话跑一次提取管线（US-21）。
  Future<int> extractMemoriesManually() async {
    final sid = currentSessionId;
    if (sid == null || sessionTurns.isEmpty) return 0;
    return _runExtraction(sessionTurns.toList(), sessionId: sid);
  }

  Future<int> _runExtraction(
    List<SessionTurn> turns, {
    String? sessionId,
  }) async {
    final chat = await ensureChat();
    final service = MemoryService(_db!, chat.gateway);
    final n = await service.extractFromTurns(turns, sessionId: sessionId);
    if (n > 0) await loadMemories();
    return n;
  }

  // ---- 人设（ADR-0014：本地 / 云端两个槽位）----

  /// 当前后端对应的人设卡；槽位缺失时回落到默认。
  PersonaCard activePersonaCard() {
    final want = settings.backend == 'cloud' ? 'cloud' : 'local';
    return settings
            .personas()
            .where((c) => c.id == want)
            .firstOrNull ??
        personaSlotDefault(settings.backend);
  }

  /// 保存当前槽位：只替换这一张，另一张原样保留，切后端不会互相覆盖。
  Future<void> savePersona(PersonaCard card) async {
    final cards = [...settings.personas()];
    final id = card.id.isEmpty ? settings.backend : card.id;
    final fixed = card.id == id ? card : card;
    final i = cards.indexWhere((c) => c.id == id);
    if (i >= 0) {
      cards[i] = fixed;
    } else {
      cards.add(fixed);
    }
    // 保证两张槽位都在，避免旧数据只有一张。
    for (final backend in ['local', 'cloud']) {
      if (!cards.any((c) => c.id == backend)) {
        cards.add(personaSlotDefault(backend));
      }
    }
    settings.personasJson = PersonaCard.encodeList(cards);
    settings.activePersonaId = settings.backend;
    await settings.save(_supportDir);
    notifyListeners();
  }

  /// 把当前槽位恢复成默认（本地小暖 / 云端傲娇鱼）。
  Future<void> resetPersona() async {
    await savePersona(personaSlotDefault(settings.backend));
  }

  /// 旧数据迁移：单卡 / 预设 id（companion、dafeiyu）→ local / cloud 两个槽位。
  Future<void> normalizePersonaSlots() async {
    final raw = [...settings.personas()];
    final hasLocal = raw.any((c) => c.id == 'local');
    final hasCloud = raw.any((c) => c.id == 'cloud');
    if (hasLocal && hasCloud && raw.length == 2) return;

    PersonaCard? legacyLocal;
    PersonaCard? legacyCloud;
    for (final c in raw) {
      if (c.id == 'local') legacyLocal = c;
      if (c.id == 'cloud') legacyCloud = c;
      // 旧版本：短卡（无正文）当本地，长卡（有正文）当云端。
      if (c.id != 'local' && c.id != 'cloud') {
        if (c.text.trim().isEmpty) {
          legacyLocal ??= c;
        } else {
          legacyCloud ??= c;
        }
      }
    }
    final local = legacyLocal == null
        ? localPersonaDefault
        : legacyLocal.copyWith(name: legacyLocal.name);
    final cloud = legacyCloud ?? cloudPersonaDefault;
    settings.personasJson = PersonaCard.encodeList([
      PersonaCard(
        id: 'local',
        name: local.name,
        personality: local.personality,
        style: local.style,
        catchphrase: local.catchphrase,
        addressTerm: local.addressTerm,
        boundary: local.boundary,
        text: local.text,
      ),
      PersonaCard(
        id: 'cloud',
        name: cloud.name,
        personality: cloud.personality,
        style: cloud.style,
        catchphrase: cloud.catchphrase,
        addressTerm: cloud.addressTerm,
        boundary: cloud.boundary,
        text: cloud.text,
      ),
    ]);
    settings.activePersonaId = settings.backend;
    await settings.save(_supportDir);
    notifyListeners();
  }

  /// system 消息文本：人设卡 + 核心记忆（预算内截断），每轮重建。
  /// 云端上下文大得多，长人设 + 更多记忆也能装下（ADR-0013）。
  String systemPrompt() => ChatService.buildSystemPromptWithinBudget(
    activePersonaCard(),
    activeMemories(),
    budget: settings.backend == 'cloud' ? cloudSystemBudget : systemBudgetTokens,
  );

  /// 云端 system 预算：6k 足够放长人设 + 几十条记忆，离 64k 还很远。
  static const cloudSystemBudget = 6000;

  /// 会话预算占用率（UI 指示器用）：无 service 时纯估算兜底。
  double contextUsage() {
    final service = _chatService;
    if (service != null) return service.contextUsage(sessionTurns);
    return sessionUsageEstimate(sessionTurns);
  }

  /// 扫描手动导入目录 + nobodywho 下载缓存（US-1 两条来源）。
  Future<void> rescanModels() async {
    final found = <String, int>{};
    final dir = Directory(modelsDirPath);
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        if (f is File && f.path.endsWith('.gguf')) {
          found[f.path] = f.lengthSync();
        }
      }
    }
    for (final (path, size) in nw.getCachedModels()) {
      found[path] = size.toInt();
    }
    modelFiles
      ..clear()
      ..addAll(found.entries.map((e) => ModelFile(e.key, e.value)));
    modelFiles.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  /// 按文件名启发式筛选模型角色：含 embed → 嵌入，其余 → 聊天。
  List<ModelFile> filesForRole({required bool isChat}) {
    return modelFiles.where((f) {
      final isEmbed = f.name.toLowerCase().contains('embed');
      return isChat ? !isEmbed : isEmbed;
    }).toList();
  }

  Future<void> confirmModels() async {
    settings.confirmed = true;
    settings.skipModelSetup = false;
    await settings.save(_supportDir);
    notifyListeners();
  }

  /// 「稍后配置」：没有模型也先进主界面，模型页从设置里再打开。
  Future<void> skipModelSetup() async {
    settings.confirmed = true;
    settings.skipModelSetup = true;
    await settings.save(_supportDir);
    notifyListeners();
  }

  /// 模型准备页角色指派（US-1）。嵌入模型可选，null 表示跳过。
  void assignModel({required bool isChat, required String? path}) {
    if (isChat) {
      settings.chatModelPath = path;
    } else {
      settings.embedModelPath = path;
    }
    notifyListeners();
  }

  /// US-1：内置下载（带进度回调；nobodywho 不支持续传，失败可重试）。
  Future<void> downloadModel({required bool isChat, String? url}) async {
    final target = url ?? (isChat ? chatModelUrl : embedModelUrl);
    downloadLabel = isChat ? '下载聊天模型…' : '下载嵌入模型…';
    downloadProgress = 0;
    downloadingUrl = target;
    notifyListeners();
    try {
      // 自己下，不用 nobodywho 的下载器：4B 文件 2.74 GB > 2^31，
      // 原生下载器的长度/进度在那边会溢出，表现就是「下不动」。
      final expected = modelCatalog
          .where((m) => m.url == target)
          .map((m) => m.sizeBytes)
          .firstOrNull;
      final path = await _downloadToModelsDir(
        target,
        expectedBytes: expected ?? 0,
      );
      if (isChat) {
        settings.chatModelPath = path;
      } else {
        settings.embedModelPath = path;
      }
      await settings.save(_supportDir);
      await rescanModels();
      // 已进入主页时下载即切换：重载模型使新模型生效。
      if (settings.confirmed) await reloadModels();
    } finally {
      downloadProgress = null;
      downloadLabel = null;
      downloadingUrl = null;
      notifyListeners();
    }
  }

  /// 流式下载到模型目录；支持 >2GB、跟随 hf-mirror 的 302 跳转。
  Future<String> _downloadToModelsDir(
    String url, {
    int expectedBytes = 0,
  }) async {
    final dir = Directory(modelsDirPath)..createSync(recursive: true);
    final name = Uri.parse(url).pathSegments.last;
    final dest = File(p.join(dir.path, name));
    final tmp = File('${dest.path}.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..autoUncompress = false;
    IOSink? sink;
    try {
      debugPrint('[download] start $url');
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'RAGchat/1.0');
      final resp = await req.close();
      debugPrint(
        '[download] status=${resp.statusCode} len=${resp.contentLength}',
      );
      if (resp.statusCode != 200) {
        throw StateError('下载失败：HTTP ${resp.statusCode}');
      }
      // 魔搭有些文件走 chunked、不给 content-length：退回目录里的已知体积。
      final total = resp.contentLength > 0
          ? resp.contentLength
          : expectedBytes;
      var done = 0;
      sink = tmp.openWrite();
      await for (final chunk in resp) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) {
          downloadProgress = (done / total).clamp(0.0, 1.0);
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (dest.existsSync()) await dest.delete();
      await tmp.rename(dest.path);
      debugPrint('[download] saved ${dest.path} bytes=$done');
      return dest.path;
    } catch (e) {
      await sink?.close();
      if (tmp.existsSync()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// 删除已下载模型。安全闸：活跃生成/嵌入模型与下载中文件禁删。
  /// 返回 null 表示成功；否则返回拒绝原因（供 UI snackbar）。
  Future<String?> deleteModel(String path) async {
    if (path == settings.chatModelPath || path == settings.embedModelPath) {
      return '该模型正在使用，请先切换后再删除';
    }
    if (downloadingUrl != null) {
      return '下载进行中，暂不能删除模型';
    }
    final f = File(path);
    if (!f.existsSync()) return '文件不存在（可能已被移除）';
    await f.delete();
    modelFiles.removeWhere((e) => e.path == path);
    notifyListeners();
    return null;
  }

  /// 设置页切换本地模型：保存 + 重载。
  Future<void> switchModel({required bool isChat, required String path}) async {
    if (isChat) {
      settings.chatModelPath = path;
    } else {
      settings.embedModelPath = path;
    }
    await settings.save(_supportDir);
    await reloadModels();
    notifyListeners();
  }

  /// US-1 手动导入兜底：SAF 选文件 → 流式拷贝进模型目录（带进度）。
  Future<void> importModelFile(PlatformFile file) async {
    Directory(modelsDirPath).createSync(recursive: true);
    final out = File(p.join(modelsDirPath, file.name));
    final sink = out.openWrite();
    final total = file.lengthSync() ?? 0;
    var done = 0;
    downloadLabel = '导入 ${file.name}…';
    downloadProgress = 0;
    notifyListeners();
    try {
      await for (final chunk in file.readAsByteStream()) {
        sink.add(chunk);
        done += chunk.length;
        downloadProgress = total > 0 ? done / total : 0;
        notifyListeners();
      }
      await sink.close();
    } catch (e) {
      await sink.close();
      // 清掉半截文件，避免扫描把残文件当模型候选
      if (out.existsSync()) out.deleteSync();
      rethrow;
    } finally {
      downloadProgress = null;
      downloadLabel = null;
    }
    await rescanModels();
    if (file.name.toLowerCase().contains('embed')) {
      settings.embedModelPath ??= out.path;
    } else {
      settings.chatModelPath ??= out.path;
    }
    notifyListeners();
  }

  /// 测试接缝（主机 widget 测试）：注入 ChatService 工厂，绕开 native 模型加载。
  /// 生产恒为 null；注入后 stopGeneration/resetSession 照常走 _chatService。
  @visibleForTesting
  Future<ChatService> Function()? debugServiceFactory;

  /// widget 测试注入 AppDb（真机走 init() 开文件库）。
  @visibleForTesting
  set debugDb(AppDb db) => _db = db;

  /// widget 测试注入设置落盘目录（真机走 init() 取应用支持目录）。
  @visibleForTesting
  set debugSupportDir(String dir) => _supportDir = dir;

  /// 懒建 Gateway + ChatService（ADR-0009：嵌入模型可选）。
  Future<ChatService> ensureChat() async {
    if (_chatService != null) return _chatService!;
    if (debugServiceFactory != null) {
      _chatService = await debugServiceFactory!();
      return _chatService!;
    }
    if (settings.backend == 'cloud' && cloudApiKey.isNotEmpty) {
      final cloud = CloudGateway(
        baseUrl: settings.cloudBaseUrl,
        apiKey: cloudApiKey,
        model: settings.cloudModel,
        temperature: settings.temperature,
      );
      _cloud = cloud;
      _chatService = ChatService(
        gateway: cloud,
        contextSize: cloudContextSize,
      );
      return _chatService!;
    }
    if (settings.chatModelPath == null) {
      throw StateError('还没有选择聊天模型');
    }
    final gateway = NobodyWhoGateway(
      chatModelPath: settings.chatModelPath!,
      embedModelPath: settings.embedModelPath,
      useGpu: settings.useGpu,
      temperature: settings.temperature,
      onLoadProgress: (stage) {
        loadStage = stage;
        notifyListeners();
      },
    );
    _gateway = gateway;
    _chatService = ChatService(gateway: gateway);
    return _chatService!;
  }

  /// 进主页时预热模型（真机）。
  Future<void> warmUp() async {
    if (gatewayLoaded) return;
    if (!settings.confirmed) return;
    final cloudReady = settings.backend == 'cloud' && cloudApiKey.isNotEmpty;
    if (!modelsReady && !cloudReady) {
      // 用户选了「稍后配置」：没有模型就别去加载，也别挂红色错误条。
      loadStage = '';
      loadError = null;
      notifyListeners();
      return;
    }
    loadError = null;
    notifyListeners();
    try {
      await ensureChat();
      if (settings.backend == 'cloud' && cloudApiKey.isNotEmpty) {
        await ensureChat();
      } else {
        await _gateway?.ensureLoaded();
      }
      loadStage = '';
    } catch (e) {
      loadStage = '';
      loadError = e.toString();
    }
    notifyListeners();
  }

  Future<void> reloadModels() async {
    // 先停生成再释放：避免流式迭代中 Rust 侧模型被回收
    _chatService?.stopGeneration();
    await _gateway?.dispose();
    await _cloud?.dispose();
    _gateway = null;
    _cloud = null;
    _chatService = null;
    await warmUp();
  }

  /// 采样温度：立即生效（下次生成），不用重载模型。
  Future<void> updateTemperature(double value) async {
    settings.temperature = value;
    // 先刷 UI，再落盘：文件 IO 不该挡住滑块的即时反馈。
    notifyListeners();
    await settings.save(_supportDir);
    if (settings.backend == 'cloud' && cloudApiKey.isNotEmpty) {
      // 云端没有热更新采样器的接口，直接重建网关（不涉及模型加载）。
      await reloadModels();
    } else {
      await _gateway?.setTemperature(value);
    }
  }

  /// 切换对话后端：本地 GGUF / 云端 API。人设按槽位自动跟着换，
  /// 但**两张卡的内容都不会被覆盖**——本地的改动留在本地那张，云端同理。
  Future<void> setBackend(String backend) async {
    settings.backend = backend;
    settings.activePersonaId = backend;
    await settings.save(_supportDir);
    notifyListeners();
    await reloadModels();
  }

  /// 保存云端 API key（Keychain/Keystore），并按需重建连接。
  Future<void> setCloudKey(String key) async {
    cloudApiKey = key.trim();
    await secretStore.write(cloudKeyName, cloudApiKey.isEmpty ? null : cloudApiKey);
    notifyListeners();
  }

  /// 保存云端 baseURL / 模型名。
  Future<void> setCloudEndpoint({String? baseUrl, String? model}) async {
    if (baseUrl != null) settings.cloudBaseUrl = baseUrl.trim();
    if (model != null) settings.cloudModel = model.trim();
    await settings.save(_supportDir);
    notifyListeners();
  }

  /// 「测试连接」：GET /models，返回可用模型列表。
  Future<List<String>> testCloudConnection() {
    final g = CloudGateway(
      baseUrl: settings.cloudBaseUrl,
      apiKey: cloudApiKey,
      model: settings.cloudModel,
    );
    return g.ping();
  }

  /// US-9：停止生成。
  void stopGeneration() => _chatService?.stopGeneration();

  /// 完成一轮：写盘 + 内存列表（US-19）。由聊天页在 AnswerDone 后调用。
  Future<void> persistTurn(String question, String answer) async {
    final db = _db;
    if (db == null) return;
    // 无会话时惰性创建（首启恢复失败或测试注入空库）。
    currentSessionId ??= (await db.createSession()).id;
    sessionTurns.add(SessionTurn(question: question, answer: answer));
    await db.appendTurn(currentSessionId!, sessionTurns.last);
    notifyListeners();
  }

  /// ADR-0009：新对话——先对当前会话跑记忆提取（异步，完成后刷新记忆页），
  /// 再开新 session、清空会话、重置模型侧上下文。
  Future<void> startNewConversation() async {
    final turns = sessionTurns.toList();
    final sid = currentSessionId;
    sessionTurns.clear();
    currentSessionId = (await _db?.createSession())?.id;
    await _chatService?.resetSession();
    notifyListeners();
    // 提取放后台：不阻塞新一轮聊天；完成后 loadMemories 会 notify。
    if (turns.isNotEmpty) {
      unawaited(
        _runExtraction(turns, sessionId: sid).catchError((Object _) => 0),
      );
    }
  }

  /// 后端切换（ADR-0005）：需重新加载模型。
  Future<void> updateUseGpu(bool value) async {
    settings.useGpu = value;
    await settings.save(_supportDir);
    await reloadModels();
  }

  /// 清空数据：会话历史 + 记忆（存储统计入口用）。
  Future<void> clearAllData() async {
    await _db?.deleteAllSessions();
    for (final m in memories) {
      await _db!.deleteMemory(m.id);
    }
    sessionTurns.clear();
    currentSessionId = null;
    await loadMemories();
  }

  /// 存储占用（会话/记忆 DB + 模型文件）。
  ({int dbBytes, int modelBytes}) storageStats() {
    final db = File(p.join(_supportDir, 'rag.db'));
    return (
      dbBytes: db.existsSync() ? db.lengthSync() : 0,
      modelBytes: modelFiles.fold(0, (sum, f) => sum + f.size),
    );
  }
}

/// InheritedNotifier 注入：页面经 AppStateScope.of(context) 监听控制器。
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStateScope>()!.notifier!;

  /// 弹层/编辑器这类可能被单独测试的地方用它：拿不到状态就回落到无状态。
  static AppState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStateScope>()?.notifier;
}
