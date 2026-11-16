# ADR-0005：真机验证结论与 CPU 后端默认

日期：2026-11-14
状态：已接受
依据：规格书 §7「实现前必须验证」第一个 ticket；OnePlus PKR110（骁龙 8 至尊版 / Adreno，14.8 GB RAM）实测

## 实测数据（nobodywho 6.0.0，debug APK，真机）

| 验证项 | 结果 |
|---|---|
| 嵌入模型加载（Qwen3-Embedding-0.6B Q8_0，0.64 GB） | 冷 9.7 s / 热 1.3 s |
| encode | 1024 维；单次约 2.6–2.9 s（当时 Encoder 默认 useGpu=true，走 Vulkan） |
| 语义区分度 | 相关句 cos 0.636 vs 无关句 0.174 → 拒答阈值 0.3 落在间隔内，初值合理 |
| 生成模型加载（Qwen3-8B Q4_K_M，5.23 GB） | GPU 13.4 s / CPU 3.0 s |
| 首 token（57 token 短提示） | GPU 5.1 s / CPU 3.2–3.8 s |
| 纯 decode | GPU ≈6.9 tok/s / CPU ≈7.7–8.0 tok/s |
| 加载后可用 RAM | GPU 1.8 GB / CPU 7.4 GB |
| 双模型共存（生产配置） | 通过：CPU chat 驻留时加载 encoder 1.3 s，共存后可用仍 7.4 GB，decode 无衰减，无 OOM/LMK |

## 决策

1. **生成模型选 Qwen3-8B Q4_K_M**（成熟架构，nobodywho 可加载，验证项 1 通过）。不降 Q3、不换 4B：CPU mmap 模式下内存余量充足。
2. **默认 CPU 后端（useGpu=false）**，GPU 仅作设置项开关。理由：本机 Adreno 上 llama.cpp Vulkan 全面慢于 ARM CPU（i8mm），且 GPU 把 5.2 GB 权重拷入匿名内存（可用 RAM 7.0→1.8 GB），CPU 走 mmap 文件页缓存（7.4 GB 余量，可回收）。
3. **2× 内存规则不达标但实测通过**：规则保守（按匿名内存估），mmap 模式下权重占可回收页缓存。以实测共存为准。
4. 嵌入与生成模型**同进程共存**确认可行（US-8 单进程离线架构成立）。

## 已知限制（v1 接受，后续观察）

- 每次 ask/encode 有约 3 s 固定开销（首 token 3.2–3.8 s 不随 warmup 消失）；RAG 长提示的 prompt 处理速度待冒烟实测，过慢则降 topK/上下文或换 4B。
- nobodywho `downloadModel` 有进度回调但**不支持续传**；US-1 以进度条 + 失败重试 + 手动导入兜底，续传缺口如实告知。
- 摄取队列在 App 前台运行（解析走 compute isolate，UI 不卡）；未做前台服务通知，退后台长时间摄取可能被系统杀——几百份文档的 overnight 场景建议保持前台/充电。