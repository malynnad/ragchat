# 情景记忆用余弦检索，先暴力全表，不引向量扩展

待办第 3 条（情景记忆向量检索）开工前的范围与选型决策。嵌入能力其实早就在库里
（`NobodyWhoGateway` 的 `Encoder`、`memories.embedding` 列都建好了），缺的只是
「把问题向量化 → 找最相关的记忆 → 塞进 800 token 预算」这一段。本 ADR 定这一段怎么接。

## 状态

accepted（第 0 步已落地：范围与选型定型；阈值待真机标定回填）

## 决策

1. **范围只做记忆检索（A 方案）**。文档知识库（`documents` / `chunks` 表）暂不接回：
   产品的定位是本地记忆陪聊，不是文档问答。表留着不动，等真要做文档再捡。
2. **相似度用余弦，维度固定 1024**。依据是模型文件自己的元数据（见下「标定」），
   不是文档抄来的数字；维度写进代码常量，模型换错时第一时间报错而不是静默出垃圾结果。
3. **存储用 SQLite BLOB + 内存全量暴力检索**，不引 sqlite-vec 一类扩展。
   一条 1024 维向量 4 KB，一千条记忆 4 MB；全量点积在真机上是毫秒级。
   等到「条目 > 2000」或「单次检索 p95 > 100 ms」再升级，理由写在这里，别提前上 native。
4. **schema v6：`memories` 加 `embedding_model` / `embedded_at`**。
   向量必须记清是谁算的——换模型或换量化后旧向量就是噪音，`model_id` 不一致的条目
   一律当作没算过，后台重算，绝不让两代向量混在一个索引里。
5. **打分 = 0.7 × cosine + 0.3 × (importance / 5)**，top-k = 5，按 token 预算截断。
   纯相似度会把高重要度的长期事实（「我住杭州」）在闲聊时挤出上下文，纯重要度又回到
   现状的问题；混起来才稳。
6. **一切都可降级**：嵌入模型没装、加载失败、单条编码超时 → 静默回退纯重要度路径，
   聊天和出字不受影响。这条是硬约束：装个 App 不该因为嵌入模型坏掉变成砖。
7. **嵌入在后台异步补齐**，不进聊天主路径。记忆写入、导入备份、模型切换后各触发一次
   补齐任务，聊天提问时只读现成的向量。

## 标定

### 已实证（2026-11-25，读 GGUF 头，未加载模型）

用 `tools/gguf_metadata.py` 解析 `Qwen3-Embedding-0.6B-Q8_0.gguf` 的前 40 MB
（HTTP Range 抓头部，没有下完 600 MB）：

| 项 | 实测值 | 含义 |
|---|---|---|
| `qwen3.embedding_length` | 1024 | 维度就是 1024，代码常量按这个写 |
| `qwen3.pooling_type` | 3 | last-token 池化，不是 mean |
| `token_embd.weight` | dims=[1024, 151669] | 确认是嵌入模型，不是 0.6B 生成模型 |
| `output_norm.weight` | dims=[1024] | 与上面的维度自洽 |
| `tokenizer.ggml.add_eos_token` | True | 分词器默认追加 EOS（见风险 1） |
| `tokenizer.ggml.bos_token_id` / `eos_token_id` | 151643 | 同一 token，Qwen 系列惯例 |

### 待真机回填（设置 → 01 / MODEL → 「标定」）

标定器跑 7 组固定探针（同义改写、同义加词、地点相关、同城不同事、完全无关、
跨语言、同类不同事），报告会给出：

- 原始向量范数（判断 nobodywho 是否已经归一化；没归一化就我们自己归一化）
- 同句两次结果的一致性（判断推理有没有随机性）
- 批量与单条的最大偏差（判断 `encodeBatch` 与 `encode` 是否等价）
- 探针相似度分布 → **top-k 和阈值就按这张表定**
- 单条耗时 → 决定要不要做缓存、要不要把补齐进一步挪到后台

**在这些数字回来之前，阈值只放一个占位值（cos ≥ 0.35），并且必须写在配置里而不是散在判断中。**

### 风险

1. **last-token 池化对末位 token 敏感**。若 nobodywho 侧分词不追加 EOS，向量质量会掉。
   信号：标定里「改写同义」那对拉不开（明显低于高相似档位）就该怀疑这里。
2. **指令前缀**。Qwen3-Embedding 官方建议 query 前加 `Instruct: …\nQuery: `，passage 不加。
   标定报告会给出加与不加的 top1 对比；默认先不加，等数据说话。
3. **中文短句相似度整体偏高**，照搬英文经验（0.75/0.8 当阈值）会全军覆没。
   阈值必须按探针分布定，这也是第 0 步先标定的原因。
4. **换模型/换量化必须全量重算**，靠决策 4 的 `embedding_model` 兜住。
5. **内存**：1000 条 × 4 KB = 4 MB，可接受；上万条才需要重新算这笔账。

## 后果

- `ChatService` 的 system 组装从「按重要度截断」变成「重要度 + 检索命中」，仍受
  800 token 预算约束，超出的命中不硬塞。
- 多一个 schema 迁移（v5 → v6）和一个后台补齐队列；迁移要能处理「有记忆但无向量」的旧库。
- 备份导出仍不携带向量（当前实现即如此）：导入后按 `model_id` 重新补齐，避免跨设备
  带着不同模型的向量跑。
- 暂不引入任何 native 依赖，Android/iOS 打包不变。

## 第 0 步产出

- `app/lib/rag/vector_math.dart`：余弦、归一化、BLOB 编解码（标定与检索共用）
- `app/lib/rag/embedding_calibration.dart`：探针标定器，输出 markdown 报告
- 设置页「标定」按钮：报告进剪贴板与日志，弹框只报要点
- `tools/gguf_metadata.py`：换模型时先验维度，别用真机报错来验
- `app/test/vector_math_test.dart`、`app/test/embedding_calibration_test.dart`（15 例）

## 参考

- [sqlite-vec](https://github.com/asg017/sqlite-vec)：升级路径，真要进 SQL 检索时看这个
- [RAGFlow](https://github.com/infiniflow/ragflow)、[LightRAG](https://github.com/HKUDS/LightRAG)、
  [kotaemon](https://github.com/Cinnamon/kotaemon)：管线与检索设计的工业级做法，
  都是 Python 服务端，只能抄设计不能搬代码
- Qwen3-Embedding 模型卡：池化与指令前缀的官方说明
