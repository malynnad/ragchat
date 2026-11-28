# RAGchat

本地优先的记忆陪聊 App。模型在手机端跑，聊天记录、记忆、人设都留在本机，不联网也能用；想要更强的对话可以切到云端 API。

Flutter + [nobodywho](https://pub.dev/packages/nobodywho)（llama.cpp 的 Flutter 绑定），默认模型 Qwen3.5-4B Q4_K_M。

## 下载

1.4.1，arm64，45 MB：

- Gitee：<https://gitee.com/dannylam/ragchat/releases/tag/v1.4.1>
- GitCode：<https://gitcode.com/DannyLam/ragchat/releases/v1.4.1>

直链：

- Gitee：<https://gitee.com/dannylam/ragchat/releases/download/v1.4.1/RAGchat-1.4.1-arm64.apk>
- GitCode：<https://gitcode.com/DannyLam/ragchat/releases/download/v1.4.1/RAGchat-1.4.1-arm64.apk>

```
sha256  9a2a0b38cc4ec0e2094a980eaaba2147691eac4d1358524f1dbf817cf0c3e339
```

GitHub 只镜像代码和 tag，APK 走上面两个国内源。仓库：[Gitee](https://gitee.com/dannylam/ragchat)（主）、[GitCode](https://gitcode.com/DannyLam/ragchat)、[GitHub](https://github.com/malynnad/ragchat)。

## 功能

- 端上推理：GGUF 跑在手机 CPU 上，不联网、不花 token
- 长期记忆：从对话提取事实、偏好、事件、关系，带重要度，可编辑、可停用、可删除
- 记忆检索：装了嵌入模型就按相关性挑记忆进上下文，不装就按重要度排
- 会话持久化：重启恢复最近会话，`new` 开新对话时整理上一段
- 两槽人设：本地用短版、云端用长版，切后端自动换槽，内容互不覆盖
- 可选云端：DeepSeek 或任意 OpenAI 兼容 API，key 存系统 Keychain / Keystore
- 费用可见：云端回复显示本轮 token，设置里显示今日 / 累计估算
- 备份：导出 `.ragchat.zip`（会话 + 记忆 + 设置），不含 key 和模型文件
- 语音朗读：用系统 TTS，离线免费
- 温度三档；页头显示上下文占用；45 秒没有新 token 才停止生成

## 上下文怎么拼

每轮发给模型的消息表：

1. `system`：人设 + 当前时间 + 记忆（本地 800 token 预算，云端 6000）
2. 历史纯 Q/A（本地只带最近 10 轮 / ≤3600 token）
3. 当前问题

预计占用超过上下文 90% 时不发请求，提示开新对话。

## 开发

Flutter 3.35+，只支持 Android。

```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`--split-per-abi` 必须带：nobodywho 的 `libnobodywho_flutter.so` 单个 109 MB，合成一个包会到 287 MB。

首次构建会从 GitHub 下这个原生库，网络差可能被截断（表现为 APK 变小、启动白屏）。检查方法和替代做法见 [发版清单](docs/release-checklist.md)。

```bash
cd app && flutter test   # 172 例
```

## 第一次打开

1. 在模型准备页挑一个下载，或用「导入本地文件」选手机里的 GGUF
2. 不想等就点「稍后配置，先进入」，之后从 设置 → 01 / MODEL → 准备页 回来配
3. 配好聊天模型点「保存并开始聊天」；嵌入模型可选
4. 点左上 `new` 开始对话

## 模型

| 模型 | 体积 | 适合 |
| --- | --- | --- |
| Qwen3.5-2B Q4_K_M | 1.28 GB | 速度档，聊得动但容易跑题、复读 |
| Qwen3.5-4B Q4_K_M | 2.55 GB | 默认档 |
| Qwen3.5-9B Q4_K_M | 5.29 GB | 质量档，出字明显慢 |
| Qwen3-Embedding-0.6B Q8_0 | 639 MB | 记忆检索用，聊天不必装 |

模型不打进 APK，第一次使用时在 App 内下载，源走魔搭 ModelScope（国内直连）。也可以 `adb push` 到 App 私有目录后点「重新扫描」。

9B 的实测数据见 [docs/9B-review.md](docs/9B-review.md)。

## 常用操作

| 想做的事 | 怎么做 |
| --- | --- |
| 开新对话 | 页头左上 `new`，会把当前对话整理成记忆 |
| 改人设 | 设置 → 03 / PERSONA → 槽位「编辑」 |
| 让回答更稳 | 设置 → 04 / SAMPLING → 稳定（即时生效） |
| 朗读回复 | 气泡底部「朗读」；设置 → 06 / VOICE 开自动朗读、调语速音调 |
| 看云端花了多少 | 设置 → 05 / BACKEND 底部「今日 / 累计」 |
| 导出 / 导入备份 | 设置 → 07 / STORAGE；导入会覆盖当前会话与记忆 |
| 删掉全部聊天数据 | 设置 → 07 / STORAGE → 按住「删除聊天数据」填满 → 确认 |

## 本地 / 云端

| | 本地模型 | 云端 API |
| --- | --- | --- |
| 质量 | 2B 会跑题，4B 勉强，9B 明显更好 | DeepSeek，稳定得多 |
| 联网 | 不需要 | 必须 |
| 成本 | 0 | 按 token 计费，App 内可看估算 |
| 隐私 | 全在本机 | 对话 / 人设 / 记忆会发出去 |
| 上下文 | 8192 | 64000 |
| 首字延迟 | 3–10s（4B）/ 14–19s（9B） | 0.5–2s |

切换在 设置 → 05 / BACKEND。填 Base URL、模型名、API key，点「测试连接」会走 `GET /models` 自检（不发对话）。没填 key 时聊天继续走本地。

模型名默认 `deepseek-flash`，想更稳改成 `deepseek-v4-pro`。Base URL 默认 `https://api.deepseek.com`，用中转就换成对方地址。

## 隐私

- 本地模式：推理、记忆、会话全在本机；除了下载模型不发网络请求
- 云端模式：每轮对话、人设、记忆都会发给服务商；key 存系统 Keychain / Keystore，不写进 settings.json
- 云端用量只记在本地 `usage_log` 表，不上传
- 数据在 App 私有目录：`rag.db`（会话 / 轮次 / 记忆 / 用量）、`settings.json`
- 删除聊天数据不动模型文件；卸载 App 才会连模型一起删

## 项目结构

```text
RAGchat/
├── app/                  Flutter 应用
│   ├── lib/app/          界面：纸页组件、页面、人设、设置
│   ├── lib/chat/         SQLite、ChatService、记忆提取
│   ├── lib/rag/          模型接缝：nobodywho 网关、云端网关、预算、检索、TTS
│   ├── android/          applicationId: com.dannylam.ragchat
│   └── test/             测试（单元 + widget）
├── docs/                 adr / specs / TODO / 发版清单
├── tools/                gguf_metadata.py（读 GGUF 头验维度）
└── CONTEXT.md            术语表
```

## 文档

- [CONTEXT.md](CONTEXT.md) — 术语表
- [docs/TODO.md](docs/TODO.md) — 待办与已知坑
- [docs/release-checklist.md](docs/release-checklist.md) — 发版清单
- [docs/9B-review.md](docs/9B-review.md) — 9B 真机复盘
- [docs/adr](docs/adr) — 架构决策记录
- [docs/specs](docs/specs) — 需求与验收

## 已知限制

- 2B 会跑题、复读，温度调低能缓解。思考功能固定关闭。
- 9B 慢在 prefill，长历史首答可能到分钟级。
- 检索阈值只针对 Qwen3-Embedding-0.6B 标定过，换嵌入模型先在设置里跑「标定」。
- 只在 Android 上验证过，iOS 和桌面端没有构建目标。
- 项目尚未声明开源许可，使用前请先联系作者。

## 致谢

- 推理：[nobodywho](https://github.com/nobodywho-ooo/nobodywho)（llama.cpp）
- 设计语言：[paper-archive-ui](https://gitee.com/dannylam/paper-archive-ui)
- 默认模型：Qwen 系列 GGUF 量化（unsloth 与 Qwen 官方仓库）
