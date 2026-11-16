import 'dart:typed_data';

import 'package:ragchat/rag/model_gateway.dart';
import 'package:ragchat/rag/models.dart';

/// 测试用确定性网关（规格书 §5）：
/// - embed：FNV-1a 字符 bigram 哈希 → 256 维 L2 归一化向量。
///   维度足够大以避免哈希碰撞主导相似度；同文同向量，共享字符越多余弦越高。
/// - generate：回显消息表最后一条 user 消息中第一条资料，带 [1] 引用标记，逐字流式。
/// - lastMessages：记录最近一次收到的消息表，供测试断言历史剥离/人设。
class FakeGateway implements ModelGateway {
  static const int dims = 256;

  bool _stopped = false;

  /// 最近一次 generate 收到的完整消息表（测试断言用）。
  List<ChatMessage>? lastMessages;

  /// 可编程回复：非 null 时忽略资料回显逻辑，逐字流式输出此文本（一次）。
  String? nextResponse;

  /// 连续脚本回复：优先于 [nextResponse]，每次 generate 取队首。
  final scriptedResponses = <String>[];

  @override
  String get embedModelId => 'fake-embed';

  @override
  Future<Float32List> embed(String text) async => _embedSync(text);

  @override
  Future<List<Float32List>> embedBatch(List<String> texts) async => [
    for (final t in texts) _embedSync(t),
  ];

  Float32List _embedSync(String text) {
    final v = Float32List(dims);
    final t = text.replaceAll(RegExp(r'\s+'), '');
    // 仅 bigram：字符对比单字符判别力高，无关文本几乎无重叠，
    // 避免哈希碰撞让无关文本得分虚高。
    for (var i = 0; i + 1 < t.length; i++) {
      v[_fnv1a(t.substring(i, i + 2)) % dims] += 1.0;
    }
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    if (norm > 0) {
      norm = _sqrt(norm);
      for (var i = 0; i < dims; i++) {
        v[i] /= norm;
      }
    }
    return v;
  }

  @override
  Stream<String> generate(List<ChatMessage> messages) async* {
    lastMessages = messages;
    _stopped = false;
    // 可编程回复优先（记忆提取等协议化测试注入固定 JSON）。
    final scripted = scriptedResponses.isNotEmpty
        ? scriptedResponses.removeAt(0)
        : nextResponse;
    if (scripted != null) {
      nextResponse = null;
      for (final ch in scripted.split('')) {
        if (_stopped) return;
        yield ch;
      }
      return;
    }
    // 独立真相：逐条回显最后一条 user 消息中的资料首句，带 [n] 引用标记。
    // 测试可手算期望：资料原文 → 答案内容 → 引用映射。
    final prompt = messages.lastWhere((m) => m.role == ChatRole.user).content;
    final materials = RegExp(r'\[(\d+)\] （来源：[^\n]*）\n([^\n]+)')
        .allMatches(prompt);
    final answer = StringBuffer();
    var found = false;
    for (final m in materials) {
      found = true;
      final firstSentence = m.group(2)!.trim().split('。').first;
      answer.write('根据资料[${m.group(1)}]：$firstSentence。');
    }
    final text = found ? answer.toString() : '资料不足。';
    for (final ch in text.split('')) {
      if (_stopped) return;
      yield ch;
    }
  }

  @override
  Future<void> resetSession() async {}

  @override
  void stopGeneration() => _stopped = true;

  @override
  Future<void> dispose() async {}

  /// FNV-1a 32 位——确定性哈希，不依赖 Dart hashCode 的实现细节。
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final code in s.codeUnits) {
      h ^= code;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static double _sqrt(double x) {
    var r = x;
    for (var i = 0; i < 20; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }
}
