import '../rag/model_gateway.dart';
import '../rag/models.dart';
import '../app/format.dart' show nowLabel;
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

  /// 最近一轮的云端用量；本地网关返回 null。
  TokenUsage? get lastUsage =>
      gateway is UsageReporting ? (gateway as UsageReporting).lastUsage : null;

  /// 记忆段的收尾约束。小模型在「记忆里没这条」时也会顺着往下编
  /// （真实反馈：问它昨天去博物馆的细节，它一本正经地假装记得），
  /// 一句显式禁令比事后道歉有用。
  static const String memoryGuard =
      '\n（以上是你能确定的全部记忆；没列到的事就说不记得，不要编。）';

  /// 一条记忆都没有时的同等约束：这场景最容易被编（问「还记得昨天吗」，
  /// 小模型会顺着编一段）。预算不够就不加，绝不为了它挤掉人设。
  static const String emptyMemoryGuard = '（你还没有关于用户的记忆；不知道就说不记得，不要编。）';

  /// 时间行。小模型对「现在几点」几乎没有概念，不给它就分不清早晚——
  /// 早上说「晚安」、深夜说「早上好」都是这么来的。写成一句中文人话最管用。
  /// 措辞是试出来的：只说「现在是 X」时，云端模型仍会答「我看不了时间」——
  /// 它把「没有实时信息」当成了身份设定。必须明说这是准确时间、可以直接答。
  static String timeLine(DateTime now) =>
      '现在是${nowLabel(now)}；这是准确时间，用户问日期、时间、星期就直接回答，'
      '不要说不知道，也别把早晚说错。';

  /// system 的头部：人设 + 当前时间。人设为空时只留时间行。
  static String promptHead(
    PersonaCard persona, {
    bool includeCatchphrase = true,
    DateTime? now,
  }) {
    final body = persona.render(includeCatchphrase: includeCatchphrase);
    final line = timeLine(now ?? DateTime.now());
    return body.isEmpty ? line : '$body\n$line';
  }

  /// system 消息组装（ADR-0009 决策 8，公开供测试断言）：
  /// 人设卡渲染在前，核心记忆清单在后（[memories] 应已按 importance 排序）。
  /// 预算 [budget] 内截断：保证人设卡完整，记忆按序装入，装不下不硬塞。
  static String buildSystemPromptWithinBudget(
    PersonaCard persona,
    List<MemoryEntry> memories, {
    int budget = systemBudgetTokens,
    bool includeCatchphrase = true,
    DateTime? now,
  }) {
    final head = promptHead(
      persona,
      includeCatchphrase: includeCatchphrase,
      now: now,
    );
    final fitted = fitMemoriesWithinBudget(
      persona,
      memories,
      budget: budget,
      includeCatchphrase: includeCatchphrase,
      now: now,
    );
    final contents = [for (final m in fitted) m.content];
    if (head.isEmpty && contents.isEmpty) return '';
    final buf = StringBuffer();
    if (head.isNotEmpty) buf.writeln(head);
    if (contents.isNotEmpty) {
      buf.write('关于用户的长期记忆：');
      for (final c in contents) {
        buf.write('\n- $c');
      }
      buf.write(memoryGuard);
    } else if (head.isNotEmpty &&
        estimateTokens(head) + estimateTokens(emptyMemoryGuard) <= budget) {
      buf.writeln(emptyMemoryGuard);
    }
    return buf.toString().trim();
  }

  /// 预算内真正装得下的记忆（按 [memories] 的顺序贪心装入，装不下即停）。
  ///
  /// 单列出来是给「检索自检」用的：要在同一份预算下比较两种排序的差异，
  /// 不能靠人肉估算 token（ADR-0016 第 4 步）。
  static List<MemoryEntry> fitMemoriesWithinBudget(
    PersonaCard persona,
    List<MemoryEntry> memories, {
    int budget = systemBudgetTokens,
    bool includeCatchphrase = true,
    DateTime? now,
  }) {
    final head = promptHead(
      persona,
      includeCatchphrase: includeCatchphrase,
      now: now,
    );
    // 收尾那句也占预算：先预留下来，否则截断判断会少算一段。
    var used =
        estimateTokens(head) +
        estimateTokens('\n关于用户的长期记忆：') +
        estimateTokens(memoryGuard);
    final out = <MemoryEntry>[];
    for (final m in memories) {
      final cost = estimateTokens('\n- ${m.content}');
      if (used + cost > budget) break;
      used += cost;
      out.add(m);
    }
    return out;
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
