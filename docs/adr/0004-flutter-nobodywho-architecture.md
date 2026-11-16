# 架构采用 Flutter + nobodywho 全家桶，放弃 Termux/Ollama

RAG 问答知识库做成 Flutter 原生 App：nobodywho（llama.cpp 封装）在 App 内跑 GGUF 推理与嵌入，文档解析/分块/检索自建。用户在"Termux+PWA 自建 RAG"（A）与"Flutter+mobile_rag_engine"（B）之间选了 C，决定性理由是彻底摆脱 Termux 保活/幽灵进程问题；代价是放弃已装好的 Ollama 环境、承担 Flutter 工具链成本与小众库风险。

## 状态

accepted

## 备选方案

- **A：Termux Node 后端 + PWA + Ollama bge-m3**：组件最成熟、复用既有投入、迭代最快，但保活调教是长期痛点。被否决。
- **B：Flutter + mobile_rag_engine**：文档管道现成、检索召回有验证数据，但库年轻（10 个月、15 likes）、中文嵌入需额外配置、中文 PDF 解析未验证。被否决。

## 后果

- ADR-0002（Termux+PWA）被本决策取代。
- 模型需重新下载 GGUF 格式（聊天约 5GB + 嵌入约 600MB），Ollama 里的模型不能直接复用。
- PDF/DOCX 解析、分块、混合检索需用 Dart 自建；nobodywho 只提供推理/嵌入/基础 RAG。
- 中文嵌入候选 Qwen3-Embedding-0.6B GGUF，llama.cpp 支持情况实现前必须验证。
- 中量规模（几百份文档）下暴力检索足够，HNSW 非必需。