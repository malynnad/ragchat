# 陪聊 App 规格：记忆 / 人设 / 会话持久化 / 导出继承

日期：2026-11-16。基线：v2 快照（git 4a6dc2e，清理后的 RAG v2 完整版）。目的变更见 ADR-0009；本文覆盖 MVP 范围与 v2 路线图。

## 用户故事（MVP）

| 编号 | 故事 | 验收 |
|---|---|---|
| US-18 | 聊天核心：气泡 / 流式 / 停止 / 上下文占用 % / 新对话全部保留；移除引用、来源面板、分类筛选、拒答提示 | 主机：消息组装测试（人设+记忆在 system、历史纯 Q/A）；真机：流式对话正常 |
| US-19 | 会话持久化：turns 写盘，重启恢复上次会话；「新对话」开启新 session 并触发记忆提取 | 主机：会话写入/恢复测试；真机：杀进程重开，历史还在 |
| US-20 | 记忆提取：模型从对话内容提取事实条目，输出 `{add, update, deactivate}` JSON + kind + importance；触发 = 新对话时异步 + 记忆页手动 | 主机：FakeGateway 固定 JSON 断言入库/去重/停用；真机：聊「我叫Danny」→ 新对话 → 记忆页出现条目 |
| US-21 | 记忆页（第二 Tab）：按 kind 分组列表，编辑 / 删除 / 停用 / importance 展示，手动「从当前会话提取」按钮 | 主机：widget 测试增删改；真机：手动提取跑通 |
| US-22 | 人设（ADR-0011）：单卡，字段为名字 / 性格 / 说话方式 / 口癖 / 称呼 / 不做的事，逐项限字；可编辑、预览、恢复内置预设；编辑器显示 system 预算 | 主机：改口癖 → system 消息变化、落盘、恢复默认；真机：改后语气可感知、首字不慢 |
| US-23 | 导出继承：版本化 JSON（人设卡 + 记忆，不含 embedding），导出至文件 + 分享；导入按 id upsert、冲突取 updated_at 新者 | 主机：导出 → 清库 → 导入 → 内容一致；真机：导出文件可在文件管理器看到 |
| US-24 | 模型简化：默认推荐 Qwen3.5-2B Q4 速度档；嵌入模型改为可选（MVP 不强制）；移除 syncfusion_pdf / archive / xml 依赖 | 主机：目录测试；真机：只装聊天模型即可完整使用 |

## 关键设计决策

- **DB v3**（见 ADR-0009）：rag.db 升 schemaVersion 3，新增 `memories` / `sessions` / `turns` 表；旧 documents/chunks/categories 表不动。沿用幂等迁移（IF NOT EXISTS + onUpgrade 共用 _createSchema）。
- **消息组装**：system = 人设卡渲染 → 核心记忆清单（active、按 importance desc、同分按 updated_at）→ 历史纯 Q/A → 当前问题。人设+记忆合计 ≤800 token，超出砍低 importance 条目；整轮仍超 90% 容量 → `AnswerContextFull`。
- **提取协议**：复用聊天模型（不另加载）。prompt 给出现有 active 条目 + 最近对话，要求严格 JSON；解析失败静默丢弃本轮提取（绝不写脏数据）。去重阈值：字符 bigram 余弦 ≥0.75 视为同一条 → update；语义矛盾由模型显式输出 deactivate。
- **记忆生命周期**：被取代的条目 active=0 不删（可追溯）；导出只含 active 条目 + 元数据；导入后低置信不做重嵌（MVP 无 embedding）。
- **设置兼容**：settings.json 沿用 `?? 默认值` 模式扩展 personas 列表；旧字段（refusalThreshold/topK/lastCategory/customPersona）读取容忍、写入丢弃。
- **applicationId 不变**：覆盖安装继承旧 rag.db，真机验证 v2→v3 迁移。

## 测试决策

- 接缝不变：FakeGateway + ffi 内存 SQLite（`openTestStore` 升级支持 v3）。
- 新增：`app_db_test`（v3 迁移真值源 + memories/sessions/turns CRUD）、`memory_service_test`（提取入库 / 去重 / 停用 / 坏 JSON 丢弃）、`persona_test`（卡渲染 / 切换 / settings 往返）、`memory_exchange_test`（导出导入 roundtrip + 冲突 upsert）、`chat_service_test`（消息组装 / 预算 / 会话持久化）。
- 删除：rag_service / document_parser / chunker / category / docs_category_dialog / vector_store / embed_switch 测试；qa_page / session_context 测试改造为 chat_service 版。
- store_migration_test 的「手写旧 schema 作独立真相源」模式延续到 v3。

## 真机冒烟清单

1. 聊天：流式 / 停止 / 占用 % / 新对话确认弹窗。
2. 记忆：自我介绍 → 新对话（自动提取）→ 记忆页见条目；手动提取按钮；编辑 / 停用 / 删除。
3. 人设：改口癖与说话方式，语气变化；关掉重开仍是自己写的那段。
4. 导出：导出 JSON → 清空记忆 → 导入恢复。
5. 持久化：杀进程重开，会话与记忆俱在。
6. 迁移：覆盖安装旧版数据之上，v3 迁移无错、旧表数据仍在。
7. 模型：Qwen3.5-2B 速度档默认推荐；仅装聊天模型全功能可用。

## v2 路线图（本次不做）

情景记忆（turns 向量化、按问题余弦 top-k 注入 ≤1000 token、嵌入模型可选下载）；每 3–5 轮 idle 自动批量提取；last_used_at 衰减清理；会话列表页（多会话切换）。

## 风险与等待项

- 提取 prompt 质量是小模型短板（ADR-0001 教训），预期需要 2–3 轮真机迭代；JSON 容错解析是底线。
- Qwen3-1.7B 目录条目的 hf-mirror URL 未验证，验证失败则本期不加入。
- token 估算沿用保守近似；记忆条目多时 system 变长，800 预算需真机确认。
