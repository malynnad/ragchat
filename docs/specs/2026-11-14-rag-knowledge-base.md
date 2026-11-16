# RAG 问答知识库 规格说明书

日期：2026-11-14
依据：ADR-0003（目的转向）、ADR-0004（Flutter + nobodywho 架构）、CONTEXT.md 术语表、两轮 grill-with-docs 共识

## 1. 问题陈述

用户有几百份中文文档（PDF/DOCX/TXT/MD/CSV），希望在手机上用自然语言提问，得到**可追溯到原文**的答案，且文档与推理全程不出手机（隐私、离线）。云端方案不满足隐私要求；Termux+Ollama 路线有保活/幽灵进程查杀的长期痛点（ADR-0004 已否决）。

## 2. 方案概述

Flutter 原生 Android App，单进程内完成全部能力：

- **推理层**：nobodywho 6.x（llama.cpp 封装，Vulkan 加速）在 App 内跑两个 GGUF 模型——生成模型（答问）与嵌入模型（向量化）。
- **摄取管道**：文件多选导入 → 按格式解析 → 分块 → 嵌入 → 写入本地 SQLite 向量表。
- **问答管道**：问题嵌入 → 暴力余弦检索 top-k 分块 → 拼装提示词（资料 + 问题 + 引用要求）→ 流式生成带引用的答案。
- **交互**：单轮问答，答案附引用标记，点开看来源段落。模型下载完成后全程离线。

## 3. 用户故事

每条可独立验证：

- **US-1 模型准备**：首次启动进入模型准备页，下载生成模型与嵌入模型（nobodywho 内置 `huggingface:` 下载，或手动导入已下载的 GGUF 文件——国内网络兜底）。显示进度、支持续传；下载后验证模型可加载。
- **US-2 文档导入**：通过系统文件选择器多选 PDF/DOCX/TXT/MD/CSV，进入摄取队列，逐文件显示进度与状态。
- **US-3 摄取管道**：解析→分块→嵌入→入库在后台 isolate 执行，UI 不卡顿。单文件失败不阻塞队列；扫描件/加密 PDF 给出明确错误原因（"需要文字层 PDF"），不静默跳过。
- **US-4 文档管理**：文档列表显示名称/格式/分块数/摄取时间；删除文档级联删除其分块与向量；支持全量重建索引。
- **US-5 提问**：输入中文问题，答案流式输出，附引用标记 [1][2]。
- **US-6 引用核查**：点击引用标记，展示来源文档名 + 分块原文。
- **US-7 诚实拒答**：检索相似度低于阈值时，明确回答"知识库中未找到相关内容"，不编造。
- **US-8 离线**：模型就绪后，导入/提问/管理全部功能无网络可用。
- **US-9 可控生成**：生成过程可手动停止。
- **US-10 设置**：查看模型状态、存储占用；一键清空知识库（二次确认）。

## 4. 已定决策

| 决策 | 内容 | 来源 |
|------|------|------|
| 架构 | Flutter + nobodywho 全家桶，放弃 Termux/Ollama | ADR-0004 |
| 平台 | 仅 Android，debug APK + USB 安装，不上应用商店 | 共识 |
| 知识源 | 中文为主，PDF/DOCX/TXT/MD/CSV，文字层 PDF | 共识 |
| 规模与检索 | 几百份文档（约 2–5 万分块），暴力余弦检索，不用 HNSW | 共识 + ADR-0004 |
| 交互 | 单轮问答 + 引用，不做多轮 | 共识 |
| 导入 | 文件多选（SAF） | 共识 |
| 生成模型 | Qwen3.5-9B GGUF 首选（Q4_K_M 起步）；备选 Qwen3-8B / Qwen3.5-4B | 共识 + 本次核实 |
| 嵌入模型 | Qwen3-Embedding-0.6B GGUF（已验证 llama.cpp 支持，中文推荐） | 本次核实 |
| 开发环境 | Mac：Flutter SDK + Android SDK + JDK；手机开 USB 调试 | 共识 |

## 5. 测试决策（接缝设计）

深模块原则：全部 native 风险隔离在**一个**接口后，纯 Dart 逻辑在最高接缝处可完整测试。

```
UI (Flutter)
 └─ RagService ─────────────── 最高接缝：ingest / ask / documents
     ├─ DocumentParser ─────── 纯函数：bytes+格式 → TextBlock 列表
     ├─ Chunker ────────────── 纯函数：TextBlock → Chunk（按格式策略）
     ├─ VectorStore ────────── SQLite 封装：upsert/search/deleteByDoc
     └─ ModelGateway ───────── 接口：embed / generate / (rank)
         ├─ 生产：NobodyWhoGateway（唯一接触 nobodywho 的代码）
         └─ 测试：FakeGateway（确定性向量与回答）
```

- **ModelGateway**：`embed(text)→Vec`、`generate(prompt)→Stream<String>`。测试用 Fake，生产用 nobodywho 适配器。小众库的一切不确定性被关在这个接缝里。
- **DocumentParser / Chunker**：fixture 驱动单元测试（每种格式一份样本文档；中文分块边界、CSV 行组、MD 标题结构）。
- **VectorStore**：用假向量测暴力检索正确性（top-k 排序、删除级联、空库行为），不依赖模型。
- **RagService 集成测试**：FakeGateway + 真实 Parser/Chunker/Store，跑通"摄取→提问→带引用答案→拒答"全链路，无需真机与模型。

**"完成"的定义**：纯 Dart 接缝单测全绿；RagService 集成测试全绿；真机冒烟通过——导入 3 份样本文档 → 提问得到带引用答案 → 删除文档后不再引用它 → 重建索引成功。

## 6. 明确不做

- OCR（扫描件直接报错提示）；加密 PDF、HTML/RTF/PPTX/XLSX
- 多轮对话、追问、对话历史
- HNSW/ANN 索引（规模不需要）
- iOS、云同步、账号体系、应用商店分发
- 人设/长期记忆等旧陪聊项目的一切功能（ADR-0003 已废弃）
- reranker 重排（v1 纯向量检索；质量不达标时再启用 nobodywho 内置 CrossEncoder + bge-reranker-v2-m3，作为增强项而非 v1 范围）

## 7. 补充说明

### 本次核实结果（2026-11-14）

- Qwen3-Embedding-0.6B 官方 GGUF 存在，llama.cpp `/v1/embeddings` 原生支持，中文知识库评测推荐（Apache-2.0）。
- Qwen3.5 系列小尺寸为 0.8B/2B/4B/9B，**没有 8B**；用户所称"qwen3.5 8b"按 Qwen3.5-9B 处理。unsloth 与 Qwen 官方均有 GGUF。
- nobodywho 6.0.0（pub.dev 验证发布者）：`Chat.fromPath` / `chat.ask().completed()` / 内置 `huggingface:owner/repo/file.gguf` 下载 / `CrossEncoder.rankAndSort` / Metal+Vulkan 加速 / EUPL-1.2。

### 实现前必须验证（第一个 ticket）

1. nobodywho 能否加载 Qwen3.5-9B GGUF（qwen35 为新架构，其捆绑的 llama.cpp 版本支持情况未知）→ 不行则回退 Qwen3-8B GGUF（成熟架构）。
2. 内存预算：nobodywho 建议"可用 RAM ≥ 模型文件 2 倍"。9B Q4_K_M ≈ 5.5GB → 需约 11GB 可用 RAM；16GB 手机扣除系统 2–4GB 后偏紧 → 实测不达标则降 Q3_K_M 或换 Qwen3.5-4B。
3. Vulkan 在 Adreno（骁龙8至尊版）上的实际加速比与发热。
4. 嵌入 API 的确切签名对照 docs.nobodywho.ooo/flutter/embeddings-and-rag/ 确认。

### 参数初值（实测后调）

- 分块：300–500 中文字符/块，重叠约 50 字；CSV 按行组切并保留表头上下文；MD 按标题结构切。
- 检索：top-k 4–6；拒答相似度阈值实测标定。
- 生成上下文：8K 起步（nobodywho `contextSize`），资料段优先占预算。

### 其他

- 国内网络：nobodywho 内置下载走 huggingface.co，可能不可达 → US-1 的手动导入是兜底；也可评估 hf-mirror。
- 摄取几百份文档是一次性重活（嵌入计算），放后台 isolate + 前台通知，允许 overnight 跑完。
- 发热降频是手机 CPU 推理的固有现象，长答案生成速度会波动，属预期。
- 仓库目录名 `partner-memory` 与目标不符，改名待用户决定（不阻塞开发）。