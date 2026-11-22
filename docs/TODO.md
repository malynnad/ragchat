# RAGchat 待办

> 随时改、随时增删。完成了就在方框里打 `x`，别删历史。

## 进行中

- [ ] 1.2.0 待发布：云端费用显示（代码已完成、真机已验证，等出包上传）
  - [x] 请求带 `stream_options.include_usage`
  - [x] 解析 usage、按模型估费（flash 1/4、pro 4.5/13.5 元每百万 token，闲时价）
  - [x] 聊天 footer 只显示 token（↑输入 ↓输出）
  - [x] 设置 → 05 BACKEND 显示「今日 / 累计」金额与次数（存 DB `usage_log` 表）

## 下一步（按优先级）

1. [x] **9B 体验复盘**（2026-11-22）：见 [9B-review.md](9B-review.md)
   - [ ] 看门狗改「无新 token 超时」（现在总时长 60s 误杀 prefill 慢的轮次）
   - [ ] 本地后端限制历史预算（33% 上下文时首答超 60s）
   - [ ] 9B 首次加载提示「约 1 分钟」
   - [x] 温度 0.6 实测正常，维持默认
2. [ ] **导出 / 导入聊天**（US-23）：整个 `.ragchat.zip`（会话 + 记忆 + 精选设置），换机/重装不丢数据
3. [ ] **情景记忆（向量检索）**：embedding 模型已装未用，把「相关记忆自动进上下文」接上，替代纯重要度截取
4. [ ] **语音高亮**（可选）：朗读时跟着高亮当前句；对不齐风险高，优先级最低

## 已知坑

- nobodywho 的原生库从 GitHub 下载**可能被截断**（APK 变小、启动白屏、`.so` 报 missing section headers）：
  缓存目录 `app/build/nobodywho/nobodywho-cache/` 里 arm64 的 `.so` 正常约 109 MB，
  对不上就从已发布的 1.1.0 APK 里解出来覆盖，再 `flutter build apk --release --split-per-abi --target-platform android-arm64`。

## 已发布

- [x] 1.1.0：系统 TTS、两槽人设、魔搭源、9B、60 秒看门狗（2026-11-21 发布，双平台）
- [ ] 1.2.0：云端费用显示（已开发完，待发布）

## 已知问题 / 观察项

- 9B 首次加载慢（约 40–60 秒），之后出字 6–7 秒；属于机型预期
- 云端价格按闲时估算，高峰翻倍，界面标「≈」不是账单
- 发布 APK 前记得 `flutter clean`，否则 `app/build` 会涨到 9 GB
