# 模型下载源换成魔搭 ModelScope

2026-11-18 用户反馈 4B 下载「能走但非常慢」。实测：`hf-mirror.com` 只是元数据镜像，LFS 文件会 302 跳到 `cas-bridge.xethub.hf.co`（海外 Xet CDN），同样是 8 MB 区间，**0.57 MB/s**；魔搭（ModelScope）同一文件 **8.35 MB/s**，快 14 倍。4B 是 2.74 GB，这个差距是 80 分钟 vs 6 分钟。

## 状态

accepted

## 决策

1. **目录里所有 GGUF 换魔搭地址**：`https://www.modelscope.cn/models/<org>/<repo>/resolve/master/<file>`，涵盖 Qwen3.5-4B / 2B、Qwen3-0.6B、Qwen3-Embedding-0.6B（均已 HEAD 200 验证）。
2. **自己下，不用 nobodywho 的下载器**：4B 体积 2,740,937,888 B > 2^31，原生下载器在大文件上会失败（用户遇到「下不动」）。改用 Dart `HttpClient` 流式写盘，支持 >2GB、跟随 302、断点文件先写 `.part`。
3. **进度兜底**：魔搭部分文件走 chunked、没有 `content-length`；下载时用目录里登记的 `sizeBytes` 当总长度，进度条不会一直 0%。
4. **日志可观测**：下载开始/状态/落盘与云端请求都 `debugPrint` 一行，真机联调时可直接看 logcat。

## 后果

- 不再依赖 hf-mirror；国内网络下载稳定在 MB/s 级。
- 下载器失去「原生断点续传」能力（原本也没有），失败会删 `.part` 重来。
- 想换回 HF 源只需改 `model_catalog.dart` 的 URL；下载器本身与源无关。
