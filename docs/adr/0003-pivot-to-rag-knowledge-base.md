# 项目目的从人设陪聊转向 RAG 问答知识库

> **状态：superseded**（2026-11-16，项目目的再次变更为本地记忆陪聊 app，见 ADR-0009。RAG 文档管线代码移除，旧表数据保留。）

原目标是"带长期记忆的人设陪聊"（旧术语表已归档至 docs/archive/CONTEXT-partner-chat.md）。2026-11-14 用户将目的改为 RAG 问答知识库：摄取文档、本地检索、由模型生成答案。这是用户目标变更，不是技术取舍；所有基于旧目的的决策重新评估。

## 状态

accepted

## 后果

- ADR-0001（事实提取记忆）废弃：RAG 在陪聊场景被否决，如今是新目标的核心机制。
- ADR-0002（Termux+PWA 架构）待重估：Flutter RAG 库（mobile_rag_engine / nobodywho）对旧目标不合适，对新目标成为候选。
- 仓库目录名 partner-memory 与新目的不符，是否改名待定。