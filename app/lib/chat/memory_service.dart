import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../rag/model_gateway.dart';
import '../rag/models.dart';
import 'app_db.dart';

/// 记忆提取管线（ADR-0009 决策 2、US-20）。
///
/// ADR-0001 的教训在新时代依然成立：提取质量依赖小模型的 prompt 设计，
/// 这是本项目最需要真机迭代的地方。底线：解析失败静默丢弃，绝不写脏数据。
class MemoryService {
  MemoryService(this._db, this._gateway);

  final AppDb _db;
  final ChatGateway _gateway;

  /// 新条目与 active 条目的去重阈值（字符 bigram 余弦）。
  /// ≥0.6 视为同一条目走 update；矛盾交给模型显式 deactivate。
  /// 0.6 由短条目标定：6–8 字条目差一字约 0.67（"用户现在住在上海"
  /// vs "用户住在上海"）；无关文本几乎不共享 bigram，得分趋近 0。
  static const double dedupeThreshold = 0.6;

  /// 单**批**最多消费的对话轮数。长会话分批跑完，不再只取尾部——
  /// 只取尾部会让「更早聊过的事」永远进不了记忆（真实踩坑：聊了一整天博物馆，
  /// 后面又聊了别的，新建对话时博物馆早被挤出窗口）。
  static const int maxTurnsPerRun = 6;

  /// 单次提取最多跑几批（1 批 = 最多 6 轮）。9B 上一批要几十秒，
  /// 不设上限会让「新建对话」变成后台跑几分钟。
  static const int maxBatchesPerRun = 12;

  /// 提取时的「今天」：让事件能写成「2026-11-27 去了博物馆」。
  /// 可注入，测试里固定住，避免日期漂移导致断言不稳。
  DateTime Function() now = DateTime.now;

  /// 对 [turns] 分批提取并落库（按时间顺序，从头到尾跑完）。
  /// 返回写入条数（add + update）。
  /// [sessionId] 作为新条目的 source 记录（可溯源）。
  Future<int> extractFromTurns(
    List<SessionTurn> turns, {
    String? sessionId,
  }) async {
    if (turns.isEmpty) return 0;
    var written = 0;
    var batches = 0;
    for (var start = 0; start < turns.length; start += maxTurnsPerRun) {
      if (batches >= maxBatchesPerRun) {
        debugPrint(
          '记忆提取：已跑 $maxBatchesPerRun 批，剩余 ${turns.length - start} 轮留到下次',
        );
        break;
      }
      final batch = turns.sublist(
        start,
        math.min(start + maxTurnsPerRun, turns.length),
      );
      batches++;
      final active = await _db.activeMemories();
      final reply = await _collectReply(batch, active);
      final plan = _parsePlan(reply);
      // 解析失败就别继续烧 token：多半是模型这轮已经跑偏了。
      if (plan == null) break;
      written += await _applyPlan(plan, sessionId);
    }
    if (written > 0) debugPrint('记忆提取：写入 $written 条（$batches 批）');
    return written;
  }

  /// 把一份提取计划落库，返回写入条数。
  Future<int> _applyPlan(_ExtractionPlan plan, String? sessionId) async {
    final active = await _db.activeMemories();
    var written = 0;
    // 模型显式停用（矛盾/被取代）。
    for (final id in plan.deactivate) {
      if (active.any((m) => m.id == id)) {
        await _db.deactivateMemory(id);
      }
    }
    // update：按 id 整条改写（_parseItems(withId: true) 已保证 id 非空）。
    for (final item in plan.update) {
      final id = item.id;
      if (id == null) continue;
      final existing = await _db.memory(id);
      if (existing == null || !existing.active) continue;
      await _db.upsertMemory(
        existing.copyWith(
          content: item.content ?? existing.content,
          kind: item.kind ?? existing.kind,
          importance: item.importance ?? existing.importance,
          updatedAt: DateTime.now(),
        ),
      );
      written++;
    }
    // add：先对 active 条目（含本轮已 update 的）做去重。
    for (final item in plan.add) {
      final content = item.content;
      if (content == null || content.isEmpty) continue;
      final dup = await _findDuplicate(content);
      if (dup != null) {
        await _db.upsertMemory(
          dup.copyWith(
            content: content,
            kind: item.kind ?? dup.kind,
            importance: item.importance ?? dup.importance,
            updatedAt: DateTime.now(),
          ),
        );
        written++;
        continue;
      }
      await _db.upsertMemory(
        MemoryEntry(
          id: _newId(),
          content: content,
          kind: item.kind ?? MemoryKind.fact,
          importance: item.importance ?? 3,
          source: sessionId,
        ),
      );
      written++;
    }
    return written;
  }

  // ---- 往下是 _collectReply / _buildPrompt / 解析 / 去重 ----

  /// 「今天」的文本形式（YYYY-MM-DD），喂给 prompt 让事件能带上日期。
  String _todayText() {
    final d = now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 收集模型回复（一次性字符串即可，提取不需要流式 UI）。
  Future<String> _collectReply(
    List<SessionTurn> turns,
    List<MemoryEntry> active,
  ) async {
    final buf = StringBuffer();
    await for (final chunk in _gateway.generate([
      _buildPrompt(turns, active),
    ])) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  /// 提取 prompt：给现有 active 条目 + 对话，要求严格 JSON。
  /// 短句、结构固定——小模型容错优先。
  ChatMessage _buildPrompt(List<SessionTurn> turns, List<MemoryEntry> active) {
    final buf = StringBuffer();
    buf.write('今天日期：${_todayText()}。\n');
    buf.write('从下面的对话里提取值得长期记住的用户信息，分四类：\n');
    buf.write('- fact 事实：名字、住址、工作、常用设备等稳定信息\n');
    buf.write('- preference 偏好：喜欢或讨厌什么\n');
    buf.write('- event 事件：用户做过的事、去过的地方、见的人；'
        '只发生过一次也要记，并写清日期\n');
    buf.write('- relation 关系：家人、朋友、同事\n');
    if (active.isNotEmpty) {
      buf.write('已有的记忆（不要重复）：\n');
      for (final m in active) {
        buf.writeln('- [${m.id}] ${m.content}');
      }
    }
    buf.write('对话记录：\n');
    for (final t in turns) {
      buf.writeln('用户：${t.question}');
      buf.writeln('助手：${t.answer}');
    }
    buf.write(
      '''
只输出 JSON，格式：
{"add":[{"content":"新事实","kind":"fact","importance":3}],"update":[{"id":"已有id","content":"改写后的内容"}],"deactivate":["被取代的id"]}
规则：kind 只能是 fact/preference/event/relation；importance 1-5；
事件要带日期（如「2026-11-27 去博物馆看展」）；
一次性的经历也要提取，不要因为它只发生一次就跳过；
没有变化就输出空数组；不要输出 JSON 以外的文字。''',
    );
    return ChatMessage(role: ChatRole.user, content: buf.toString());
  }

  /// 容错解析：剥 ```json 围栏、截取首个 {...} 块；失败返回 null。
  static _ExtractionPlan? _parsePlan(String reply) {
    var text = reply.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final j = jsonDecode(text.substring(start, end + 1));
      if (j is! Map<String, dynamic>) return null;
      return _ExtractionPlan(
        add: _parseItems(j['add']),
        update: _parseItems(j['update'], withId: true),
        deactivate: [
          for (final e in (j['deactivate'] as List? ?? []))
            if (e is String) e,
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static List<_ExtractionItem> _parseItems(Object? raw, {bool withId = false}) {
    if (raw is! List) return const [];
    final items = <_ExtractionItem>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) continue;
      final id = e['id'] as String?;
      if (withId && (id == null || id.isEmpty)) continue;
      final content = (e['content'] as String?)?.trim();
      if (!withId && (content == null || content.isEmpty)) continue;
      final kindName = e['kind'] as String?;
      items.add(
        _ExtractionItem(
          id: id,
          content: content,
          kind:
              kindName != null &&
                  MemoryKind.values.any((k) => k.name == kindName)
              ? MemoryKind.values.byName(kindName)
              : null,
          importance: (e['importance'] as num?)?.toInt().clamp(1, 5),
        ),
      );
    }
    return items;
  }

  /// 去重：与 active 条目算字符 bigram 余弦，取最高分且过阈值者。
  Future<MemoryEntry?> _findDuplicate(String content) async {
    final active = await _db.activeMemories();
    MemoryEntry? best;
    var bestScore = 0.0;
    for (final m in active) {
      final score = _bigramSimilarity(content, m.content);
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    return bestScore >= dedupeThreshold ? best : null;
  }

  String _newId() =>
      'mem-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}

/// 字符 bigram 余弦相似度（纯函数，文本级去重）。
/// 与 FakeGateway 的向量 bigram 同思路，但纯 Dart 实现不依赖嵌入模型。
double _bigramSimilarity(String a, String b) {
  Map<String, int> grams(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), '');
    final m = <String, int>{};
    for (var i = 0; i + 1 < t.length; i++) {
      final g = t.substring(i, i + 2);
      m[g] = (m[g] ?? 0) + 1;
    }
    return m;
  }

  final ga = grams(a), gb = grams(b);
  if (ga.isEmpty || gb.isEmpty) return 0;
  var dot = 0, na = 0, nb = 0;
  for (final v in ga.values) {
    na += v;
  }
  for (final v in gb.values) {
    nb += v;
  }
  for (final e in ga.entries) {
    dot += e.value * (gb[e.key] ?? 0);
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (_sqrtInt(na) * _sqrtInt(nb));
}

double _sqrtInt(int x) {
  var r = x.toDouble();
  for (var i = 0; i < 20; i++) {
    r = (r + x / r) / 2;
  }
  return r;
}

class _ExtractionItem {
  const _ExtractionItem({this.id, this.content, this.kind, this.importance});
  final String? id;
  final String? content;
  final MemoryKind? kind;
  final int? importance;
}

class _ExtractionPlan {
  const _ExtractionPlan({
    this.add = const [],
    this.update = const [],
    this.deactivate = const [],
  });
  final List<_ExtractionItem> add;
  final List<_ExtractionItem> update;
  final List<String> deactivate;
}
