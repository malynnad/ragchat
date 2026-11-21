import 'dart:typed_data';

import 'models.dart';

/// 聊天网关接缝：generate/reset/stop 全部原生风险隔离在此接口后。
/// 生产实现 NobodyWhoGateway 是唯一接触 nobodywho 的代码；
/// 测试用 FakeGateway 提供确定性回复。
/// ADR-0009：MVP 只需要聊天；嵌入（v2 情景记忆）拆到独立接口。
abstract interface class ChatGateway {
  /// 流式生成（ADR-0006 消息表驱动）：system + 历史纯 Q/A + 当前问题。
  Stream<String> generate(List<ChatMessage> messages);

  /// 新对话：清空模型侧会话上下文（ADR-0006）。
  Future<void> resetSession();

  /// 手动停止生成。
  void stopGeneration();

  Future<void> dispose();
}

/// 可选用量上报：云端网关实现它，本地网关没有这个概念。
abstract interface class UsageReporting {
  /// 最近一次生成的用量；失败/未返回时为 null。
  TokenUsage? get lastUsage;
}

/// 嵌入网关接缝（v2 情景记忆用；MVP 不要求实现）。
abstract interface class EmbedGateway {
  Future<Float32List> embed(String text);

  Future<List<Float32List>> embedBatch(List<String> texts);

  /// 当前嵌入模型标识（生产为文件路径）。
  String get embedModelId;
}

/// 完整网关 = 聊天 + 嵌入（FakeGateway / 生产 Gateway 都实现全量）。
abstract interface class ModelGateway implements ChatGateway, EmbedGateway {}
