# RAGchat

本地优先的**记忆陪聊 App**：模型默认在手机端跑，聊天记录、记忆、人设全部留在本机，不联网也能用；想要更强的对话可以随时切到云端 API。

界面按「纸页与档案」设计语言做成一本摊开的档案册——暖白纸面、编号与细线、克制的玻璃。  
技术栈 Flutter + [nobodywho](https://pub.dev/packages/nobodywho)（llama.cpp 的 Flutter 绑定），默认模型 Qwen3.5-4B Q4_K_M。

| 聊天 | 记忆 | 设置 |
| --- | --- | --- |
| ![聊天](docs/screenshots/chat.png) | ![记忆](docs/screenshots/memory.png) | ![设置](docs/screenshots/settings.png) |

## 下载

最新版本 **1.2.0**（arm64，约 45 MB）：

- **Gitee**：<https://gitee.com/dannylam/ragchat/releases/tag/v1.2.0>
- **GitCode**：<https://gitcode.com/DannyLam/ragchat/releases/v1.2.0>

直链（点开就开始下载）：

- Gitee：<https://gitee.com/dannylam/ragchat/releases/download/v1.2.0/RAGchat-1.2.0-arm64.apk>
- GitCode：<https://gitcode.com/DannyLam/ragchat/releases/download/v1.2.0/RAGchat-1.2.0-arm64.apk>

```
sha256  d6fe1b7c2aaad12f57e4cec3daca86fc31f86076e37958838cab37dcb61de1dc
```

GitHub 只镜像代码和 tag，APK 走上面两个国内源（GitHub 上传慢，也省得两边各传一遍）。

仓库：

- Gitee（主）：<https://gitee.com/dannylam/ragchat>
- GitCode：<https://gitcode.com/DannyLam/ragchat>
- GitHub（镜像）：<https://github.com/malynnad/ragchat>

## 目录

- [功能](#功能)
- [它是怎么工作的](#它是怎么工作的)
- [快速开始](#快速开始)
- [模型怎么选](#模型怎么选)
- [日常使用](#日常使用)
- [语音](#语音)
- [对话后端：本地 / 云端](#对话后端本地--云端)
- [隐私](#隐私)
- [项目结构](#项目结构)
- [开发](#开发)
- [文档](#文档)
- [已知限制](#已知限制)

## 功能

- **端上推理**：GGUF 直接在手机 CPU 上跑，不走云端，不花 token 钱。默认 4B Q4；想快换 2B，想要更稳可上 9B（手机上明显更慢）。
- **可选云端**：设置里能切到 DeepSeek（或任何 OpenAI 兼容）API，对话质量高一截；key 存系统 Keychain/Keystore，不用时切回本地。
- **云端费用可见**：云端回复底部显示本轮 token（↑输入 ↓输出）；设置 → `05 / BACKEND` 显示「今日 / 累计」的估算金额与调用次数（按官方闲时价，仅供参考）。
- **模型可后配**：首次打开不想等下载，点「稍后配置，先进入」也能看界面，模型随时在设置里补。
- **长期记忆**：从对话里提取「事实 / 偏好 / 事件 / 关系」四类记忆条目，带重要度；可见、可编辑、可停用、可删除。每轮按重要度排序注入 system。
- **会话持久化**：关掉 App 再打开，最近会话和轮次都在；「new」开新对话时自动整理上一段对话的记忆。
- **两槽人设，同一个人**：本地用小模型扛得住的短版「大肥鱼」（六字段，≈139 token），云端用同一个人的长版（≈1.3k 字，整段编辑）。切后端自动换槽位，内容各自保存、互不覆盖。
- **语音朗读**：助手回复可一键朗读（系统 TTS，离线免费）；设置里能开新回复自动朗读、调语速与音调。
- **采样可调**：温度三档（稳定 0.4 / 平衡 0.6 / 活跃 0.9），即时生效。
- **上下文有数**：页头实时显示会话占用百分比；本地后端只带最近 10 轮 / ≤3600 token 的历史，避免 9B 首答被长历史拖死。
- **守住边界**：45 秒没有新 token 才自动停止（另设 10 分钟硬上限），不会误杀 prefill 慢的正常轮次；键盘弹起时底部导航滑走；删库要按住进度条填满才弹确认。

## 它是怎么工作的

![架构](docs/architecture.svg)

每轮问答的消息表是这样拼的（ADR-0006 / ADR-0009）：

1. `system` = 人设渲染 + 核心记忆清单（按重要度排序；本地 800 / 云端 6000 token 预算）
2. 历史轮次，只放纯 Q/A（本地裁剪到最近 10 轮 / ≤3600 token，云端全量）
3. 当前问题

生成走 `ChatService` 的流式接口，逐 token 更新气泡；预计占用超过上下文 90% 时不发起生成，改为引导开新对话。

几个关键取舍写在 ADR 里：

| 决策 | 结论 |
| --- | --- |
| 记忆形态 | 核心记忆用事实条目（字符 bigram 余弦去重），情景记忆留 v2 |
| 人设 | 单卡拆成 local / cloud 两个槽位，同一角色两种长度（ADR-0011、0014） |
| 界面 | 纸页与档案，单一纸墨色，不做多色主题（ADR-0012） |
| 思考 | 固定关闭：小模型开思考会自言自语、还会把思考内容喷进气泡 |
| 模型目录 | 聊天只留 2B / 4B / 9B + 嵌入 0.6B；0.6B 聊天档已删（太弱） |
| 下载源 | 魔搭 ModelScope（国内直连），自己实现下载器支持 >2GB（ADR-0015） |

## 快速开始

### 环境

- Flutter 3.35 及以上（SDK 约束 `^3.14.0`），Android 设备或模拟器
- 首次构建会拉 nobodywho 的 native 依赖（约 109 MB，从 GitHub release 下载），耗时几分钟

```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

- `--split-per-abi` 必须带：nobodywho 的 `libnobodywho_flutter.so` 单个就 109 MB，合成一个 APK 是 287 MB；按 ABI 拆开并压缩 `.so` 后，arm64 包只有 **45 MB** 左右。
- `--target-platform android-arm64` 只出手机用的那一份，跳过 x86_64，少下一次 81 MB 的库。
- 原生库下载**可能被截断**（APK 变小、启动白屏）：检查 `app/build/nobodywho/nobodywho-cache/.../libnobodywho_flutter.so` 是否约 109 MB，不对就从上一版 APK 里解出来覆盖，详见 [发版清单](docs/release-checklist.md)。

### 第一次打开

1. 进模型准备页，从「下载候选模型」里挑一个下载（会显示进度），或者用「导入本地文件」选手机里的 GGUF
2. 不想现在下载就点 **「稍后配置，先进入」**——主界面能看，顶部会挂一条提示，之后从设置 → 01 / MODEL → 「准备页」回来配
3. 配好聊天模型就点「保存并开始聊天」；嵌入模型可选，只有 v2 情景记忆才用得上
4. 点左上 `new` 开始对话

## 模型怎么选

| 模型 | 体积 | 适合 |
| --- | --- | --- |
| Qwen3.5-2B Q4_K_M | 1.28 GB | 速度档：聊得动，但容易跑题、复读 |
| Qwen3.5-4B Q4_K_M | 2.55 GB | 默认档：2B 语无伦次时换它，手机上仍算能用 |
| Qwen3.5-9B Q4_K_M | 5.29 GB | 质量档：更稳更少跑题，出字明显慢（短上下文 14–19s/轮，长历史会到分钟级） |
| Qwen3-Embedding-0.6B Q8_0 | 639 MB | v2 情景记忆用，聊天不必装 |

模型不下进 APK，第一次使用时在 App 内下载；源走**魔搭 ModelScope**（国内直连，实测 8 MB/s 级；hf-mirror 的 LFS 会跳海外 Xet，只有 0.5 MB/s）。也可以电脑 `adb push` 到 App 私有目录后点「重新扫描」，或直接用文件选择器导入。

9B 的实测数据与结论见 [docs/9B-review.md](docs/9B-review.md)。

## 日常使用

| 想做的事 | 怎么做 |
| --- | --- |
| 开新对话 | 页头左上 `new`；会把当前对话整理成记忆 |
| 改人设 | 设置 → 03 / PERSONA → 某一槽位「编辑」；短人设填六项，长人设整段编辑 |
| 让回答更稳 | 设置 → 04 / SAMPLING → 稳定（即时生效） |
| 朗读回复 | 气泡底部「朗读」；设置 → 06 / VOICE 开自动朗读、调语速/音调 |
| 看云端花了多少 | 设置 → 05 / BACKEND 底部「今日 / 累计」 |
| 删掉全部聊天数据 | 设置 → 07 / STORAGE → 按住「删除聊天数据」直到填满 → 确认（用量账本一起清） |
| 看上下文用了多少 | 页头右上百分比；满 90% 会提示开新对话 |

## 语音

用手机自带的 TTS 引擎，离线、免费、不耗流量，不需要任何 key。

- 每条助手回复底部「朗读 / 停止」，同一时间只读一条
- 设置 → `06 / VOICE`：新回复自动朗读、语速（20%–80%）、音调（0.70–1.30）
- 发音人跟随系统默认 TTS 引擎；想换音色去系统设置里换成第三方引擎（如讯飞语音引擎），App 不内置音色选择

## 对话后端：本地 / 云端

| | 本地模型 | 云端 API |
| --- | --- | --- |
| 质量 | 2B 会跑题，4B 勉强，9B 明显更好 | DeepSeek，稳定得多 |
| 联网 | 不需要 | 必须 |
| 成本 | 0 | 按 token 计费，App 内可看估算 |
| 隐私 | 全在本机 | 对话 / 人设 / 记忆会发出去 |
| 上下文 | 8192 | 64000 |
| 首字延迟 | 3–10s（4B）/ 14–19s（9B，短上下文） | 0.5–2s（看网络） |

切换在设置 → `05 / BACKEND`：选「云端 API」后填 Base URL、模型名、API key，点「测试连接」会走 `GET /models` 自检（不发对话、不烧 token）。没填 key 时聊天自动继续走本地。

模型名默认 `deepseek-flash`（便宜快）；想更稳更强改成 `deepseek-v4-pro`。切换后端会换用对应槽位的人设（都是「大肥鱼」，只是长短不同）。

Base URL 默认 `https://api.deepseek.com`；用中转就换成对方地址，末尾带不带 `/` 都行。

## 隐私

- **本地模式**下推理、记忆、会话全部在本机；除了下载模型，App 不发起网络请求。
- 切到**云端模式**后，每轮对话、人设、记忆都会发给服务商；API key 存在系统 Keychain / Keystore 里，不写进 settings.json。
- 云端用量（token 数与估算费用）只记在本地 `usage_log` 表，不上传。
- 数据落在 App 私有目录：`rag.db`（会话 / 轮次 / 记忆 / 用量）、`settings.json`（人设、温度、模型路径）。
- 删除聊天数据不会动模型文件；卸载 App 才会连模型一起删。

## 项目结构

```text
RAGchat/
├── app/                     Flutter 应用
│   ├── lib/
│   │   ├── app/             界面：纸页组件、页面、人设编辑器、设置
│   │   ├── chat/            会话与记忆：SQLite、ChatService、记忆提取
│   │   ├── rag/             模型接缝：nobodywho 网关、云端网关、预算、模型目录、TTS
│   │   └── main.dart        入口（直接进主页 / 模型准备页）
│   ├── assets/branding/     图标
│   ├── android/             Android 工程（applicationId: com.dannylam.ragchat）
│   └── test/                107 个测试（单元 + widget）
├── docs/
│   ├── adr/                 架构决策记录
│   ├── specs/               需求规格
│   ├── screenshots/         README 截图
│   ├── architecture.svg     架构图
│   ├── TODO.md              待办清单
│   ├── release-checklist.md 发版清单
│   └── 9B-review.md         9B 真机复盘
├── CONTEXT.md               术语表
└── QA说明书.md               验收清单
```

## 开发

```bash
cd app
dart analyze                 # 静态检查
flutter test                 # 107 个测试，约 15 秒
flutter build apk --release --split-per-abi --target-platform android-arm64
```

界面规范来自 [paper-archive-ui](https://gitee.com/dannylam/paper-archive-ui)：暖白纸 + 档案编号 + 只在交互层用玻璃。设计令牌集中在 `app/lib/app/paper.dart`，改配色只要动 `PaperPalette`。

## 文档

- [CONTEXT.md](CONTEXT.md) — 术语表
- [docs/TODO.md](docs/TODO.md) — 待办与已知坑
- [docs/release-checklist.md](docs/release-checklist.md) — 发版清单（含 nobodywho 缓存坑）
- [docs/9B-review.md](docs/9B-review.md) — 9B 真机体验复盘
- [docs/adr](docs/adr) — 架构决策（0009 陪聊转向、0011/0014 人设、0012 纸页界面、0013/0015 云端与下载源）
- [docs/specs](docs/specs) — 需求与验收
- [docs/工作原理与模型选型.md](docs/工作原理与模型选型.md) — 早期模型对比记录

## 已知限制

- 2B 模型会跑题、会复读；温度调低能缓解，不能根治。**思考功能不可用**，已固定关闭。
- 9B 慢在 prefill：长历史首答可能到分钟级，已通过裁剪历史缓解，但体验仍取决于设备与温度。
- 情景记忆（对话向量检索）还没做，`embedModelPath` 目前只是占位。
- 导出 / 导入继承（US-23）未实现，换设备暂时只能靠整份数据库。
- 只在 Android 上验证过；iOS 和桌面端没有构建目标。
- 项目尚未声明开源许可，使用前请先联系作者。

## 致谢

- 推理：[nobodywho](https://github.com/nobodywho-ooo/nobodywho)（llama.cpp）
- 设计语言：[paper-archive-ui](https://gitee.com/dannylam/paper-archive-ui)
- 默认模型：Qwen 系列 GGUF 量化（unsloth 与 Qwen 官方仓库）
