// 聊天数据模型（ADR-0009：RAG 数据结构已随管线移除）。

/// 聊天消息角色（纯 Dart，与 nobodywho Message 解耦，ADR-0006）。
enum ChatRole { system, user, assistant }

/// 聊天消息：ChatService 组装消息表的单元。
class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final ChatRole role;
  final String content;
}

/// 会话轮次：纯 Q/A（ADR-0006）。持久化到 turns 表（ADR-0009）。
class SessionTurn {
  const SessionTurn({required this.question, required this.answer});

  final String question;
  final String answer;
}

/// 云端返回的用量（OpenAI 兼容的 usage 字段）。
class TokenUsage {
  const TokenUsage({required this.promptTokens, required this.completionTokens});

  final int promptTokens;
  final int completionTokens;

  int get totalTokens => promptTokens + completionTokens;
}

/// 问答事件流（US-18：流式 + 容量 + 错误）。
sealed class AnswerEvent {}

class AnswerToken extends AnswerEvent {
  AnswerToken(this.text);
  final String text;
}

class AnswerDone extends AnswerEvent {}

/// 上下文容量将满（ADR-0006）：不发起生成，引导开启新对话。
class AnswerContextFull extends AnswerEvent {
  AnswerContextFull({required this.projectedTokens, required this.contextSize});
  final int projectedTokens;
  final int contextSize;
}

class AnswerError extends AnswerEvent {
  AnswerError(this.message);
  final String message;
}
