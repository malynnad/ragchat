import '../rag/model_gateway.dart';
import '../rag/models.dart';
import '../rag/token_budget.dart'
    show
        contextSafetyFactor,
        estimateTokens,
        projectedUsage,
        sessionUsageEstimate,
        systemBudgetTokens;
import '../app/persona.dart';
import 'app_db.dart';

/// 聊天核心服务（替代 RagService，ADR-0009）：
/// 组装 system（人设卡 + 核心记忆）→ 历史纯 Q/A → 当前问题 → 流式生成。
/// 无检索、无引用、无拒答；容量预检 + 新对话语义延续 ADR-0006。
class ChatService {
  ChatService({required this.gateway, this.contextSize = 8192});

  final ChatGateway gateway;

  /// 模型上下文容量（ADR-0006 预算预检用）。
  final int contextSize;

  /// system 消息组装（ADR-0009 决策 8，公开供测试断言）：
  /// 人设卡渲染在前，核心记忆清单在后（[memories] 应已按 importance 排序）。
  /// 预算 [budget] 内截断：保证人设卡完整，记忆按序装入，装不下不硬塞。
  static String buildSystemPromptWithinBudget(
    PersonaCard persona,
    List<MemoryEntry> memories, {
    int budget = systemBudgetTokens,
    bool includeCatchphrase = true,
  }) {
    final head = persona.render(includeCatchphrase: includeCatchphrase);
    final used0 = estimateTokens(head) + estimateTokens('\n关于用户的长期记忆：');
    final contents = <String>[];
    var used = used0;
    for (final m in memories) {
      final cost = estimateTokens('\n- ${m.content}');
      if (used + cost > budget) break;
      used += cost;
      contents.add(m.content);
    }
    if (head.isEmpty && contents.isEmpty) return '';
    final buf = StringBuffer();
    if (head.isNotEmpty) buf.writeln(head);
    if (contents.isNotEmpty) {
      buf.write('关于用户的长期记忆：');
      for (final c in contents) {
        buf.write('\n- $c');
      }
    }
    return buf.toString().trim();
  }

  /// 容量预检（ADR-0006）：预计超 90% 不发起生成，引导开启新对话。
  /// [systemPrompt] 为已组装好的人设+记忆文本。
  Stream<AnswerEvent> ask(
    String question, {
    required String systemPrompt,
    List<SessionTurn> history = const [],
  }) async* {
    final projected = projectedUsage(
      systemPrompt: systemPrompt,
      history: history,
      question: question,
    );
    if (projected > contextSize * contextSafetyFactor) {
      yield AnswerContextFull(
        projectedTokens: projected,
        contextSize: contextSize,
      );
      return;
    }

    final messages = buildMessages(
      question: question,
      systemPrompt: systemPrompt,
      history: history,
    );
    final answerBuf = StringBuffer();
    await for (final token in gateway.generate(messages)) {
      answerBuf.write(token);
      yield AnswerToken(token);
    }
    yield AnswerDone();
  }

  /// 组装消息表（公开供测试断言）：
  /// system（人设+记忆）→ 历史纯 Q/A → 当前问题。
  List<ChatMessage> buildMessages({
    required String question,
    required String systemPrompt,
    List<SessionTurn> history = const [],
  }) {
    final messages = <ChatMessage>[
      if (systemPrompt.isNotEmpty)
        ChatMessage(role: ChatRole.system, content: systemPrompt),
    ];
    for (final t in history) {
      messages.add(ChatMessage(role: ChatRole.user, content: t.question));
      messages.add(ChatMessage(role: ChatRole.assistant, content: t.answer));
    }
    messages.add(ChatMessage(role: ChatRole.user, content: question));
    return messages;
  }

  /// 会话预算占用率（UI 指示器用，0=新对话，1=应开启新对话）。
  double contextUsage(List<SessionTurn> history) =>
      sessionUsageEstimate(history, contextSize: contextSize);

  /// 新对话：清空模型侧上下文（ADR-0006）。
  Future<void> resetSession() => gateway.resetSession();

  /// 手动停止当前生成（US-9 延续）。流会提前收尾并照常发 AnswerDone。
  void stopGeneration() => gateway.stopGeneration();

  Future<void> dispose() => gateway.dispose();
}
