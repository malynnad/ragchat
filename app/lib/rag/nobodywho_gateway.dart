import 'dart:typed_data';

import 'package:nobodywho/nobodywho.dart' as nw;

import 'model_gateway.dart';
import 'models.dart';

/// 生产 Gateway（规格书 §5）：唯一接触 nobodywho 的代码。
/// 加载/OOM/后端差异等 native 不确定性全部关在这个接缝里。
/// ADR-0009：嵌入模型可选（MVP 不强制）；embed 调用时才惰性加载，
/// 纯聊天使用不付出 ~600MB 嵌入模型的内存与加载时间。
class NobodyWhoGateway implements ModelGateway {
  NobodyWhoGateway({
    required this.chatModelPath,
    this.embedModelPath,
    this.useGpu = false, // ADR-0005：本机 Adreno 上 CPU 全面优于 Vulkan
    this.contextSize = 8192,
    this.temperature = 0.7,
    this.onLoadProgress,
  });

  /// system 提示兜底；每轮 complete() 的消息表首条 system 消息会覆盖它
  /// （ChatService 组装人设卡 + 记忆，ADR-0009）。
  static const systemPrompt = '你是一个聊天助手。';

  final String chatModelPath;

  /// null = 未安装嵌入模型（MVP 允许；embed 调用抛错）。
  final String? embedModelPath;
  final bool useGpu;
  final int contextSize;

  /// 采样温度（0=几乎固定，1.5=很发散）。手机上聊天常用 0.5–0.9。
  final double temperature;
  final void Function(String stage)? onLoadProgress;

  nw.Chat? _chat;
  nw.Encoder? _encoder;
  Future<void>? _chatLoading;
  Future<void>? _encoderLoading;

  bool get loaded => _chat != null;

  @override
  String get embedModelId => embedModelPath ?? '';

  /// 并发安全的幂等加载；失败后清空缓存的 Future，允许重试。
  Future<void> ensureLoaded() => _ensureChat();

  Future<void> _ensureChat() {
    return _chatLoading ??= _loadChat().catchError((Object e) {
      _chatLoading = null;
      throw e;
    });
  }

  Future<void> _ensureEncoder() {
    if (embedModelPath == null) {
      throw StateError('未安装嵌入模型（MVP 聊天不需要；v2 情景记忆需要）');
    }
    return _encoderLoading ??= _loadEncoder().catchError((Object e) {
      _encoderLoading = null;
      throw e;
    });
  }

  Future<void> _loadChat() async {
    onLoadProgress?.call('加载生成模型…');
    _chat = await nw.Chat.fromPath(
      modelPath: chatModelPath,
      contextSize: contextSize,
      useGpu: useGpu,
      // 官方推荐关思考的方式（setAllowThinking 已 deprecated）
      // 思考一律关掉：2B 模型开了会自言自语、还会把思考内容喷进聊天气泡。
      templateVariables: const {'enable_thinking': false},
      sampler: nw.SamplerPresets.temperature(temperature: temperature),
      systemPrompt: systemPrompt,
      // ADR-0006：上下文满时报错而非静默遗忘旧轮；
      // 容量由 Dart 侧预算预检 + 提示开启新对话管理。
      contextShift: const nw.ContextShiftOptions(enabled: false),
    );
    onLoadProgress?.call('模型就绪');
  }

  Future<void> _loadEncoder() async {
    onLoadProgress?.call('加载嵌入模型…');
    _encoder = await nw.Encoder.fromPath(
      modelPath: embedModelPath!,
      useGpu: useGpu,
    );
    onLoadProgress?.call('模型就绪');
  }

  @override
  Future<Float32List> embed(String text) async {
    await _ensureEncoder();
    return _encoder!.encode(text: text);
  }

  @override
  Future<List<Float32List>> embedBatch(List<String> texts) async {
    await _ensureEncoder();
    return _encoder!.encodeBatch(texts: texts);
  }

  @override
  Stream<String> generate(List<ChatMessage> messages) async* {
    await _ensureChat();
    // ADR-0006：整表替换历史并续写。消息表由 ChatService 组装：
    // system（人设卡+记忆）→ 历史纯 Q/A → 当前问题。
    final nwMessages = [
      for (final m in messages)
        switch (m.role) {
          ChatRole.system => nw.systemMessage(m.content),
          ChatRole.user => nw.userMessage(m.content),
          ChatRole.assistant => nw.assistantMessage(m.content),
        },
    ];
    yield* _chat!.complete(nwMessages);
  }

  /// 热调温度：不重载模型，下一次生成即用新采样器。
  Future<void> setTemperature(double value) async {
    await _ensureChat();
    await _chat!.setSamplerConfig(
      nw.SamplerPresets.temperature(temperature: value),
    );
  }

  @override
  Future<void> resetSession() async {
    await _chat?.resetContext(systemPrompt: systemPrompt, tools: const []);
  }

  @override
  void stopGeneration() => _chat?.stopGeneration();

  @override
  Future<void> dispose() async {
    // Rust 侧由 GC finalizer 回收；置空引用使其可回收
    _chat = null;
    _encoder = null;
    _chatLoading = null;
    _encoderLoading = null;
  }
}
