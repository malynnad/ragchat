# 增加云端对话后端（DeepSeek / OpenAI 兼容）

2026-11-18 用户提出：端上 2B/4B 的对话能力不够，接 DeepSeek API 是不是会强很多。结论是会强一个量级，但「本地优先、记忆不出门」是本项目的卖点，所以不做成替换，而是**混合**：默认本地，用户自己填 key 才走云端。

## 状态

accepted

## 决策

1. **复用 ChatGateway 接缝**：新增 `CloudGateway implements ChatGateway`，`ChatService` 完全不知道对面是 GGUF 还是云；流式、停止、看门狗、消息组装都不用改。
2. **OpenAI 兼容协议**：`POST {base}/chat/completions`，`stream: true`，解析 SSE 的 `data:` 行。baseURL 默认 `https://api.deepseek.com`，可换成任意兼容中转；末尾带不带 `/` 都能拼对。
3. **key 不进 settings.json**：新增 `SecretStore` 接缝，生产用 `flutter_secure_storage`（Android Keystore / iOS Keychain），测试用内存实现。
4. **后端可切**：`settings.backend = local | cloud`；切云端但没填 key 时自动回落本地，并在设置页提示，不静默失败。
5. **上下文预算跟着后端走**：本地 8192，云端 64000（DeepSeek 64K 留余量），`ChatService(contextSize:)` 已有参数直接传。
6. **成本与隐私显性化**：设置页云端分组写明「每轮对话、人设、记忆都会发给服务商」；`测试连接` 走 `GET /models`，不发对话、不烧 token。
7. **错误可读**：401/402/403/429 与超时、断网各给一句人话，不透传原始 JSON。

## 后果

- 训练/推理的本地性只在 `backend=local` 时成立；README 与 App 内都要说清楚。
- 云端温度没有热更新接口：改温度会重建网关（不涉及模型加载，代价很小）。
- `flutter_secure_storage` 引入原生依赖，首次构建需重新 `pub get`。
- 仍不做「自动回落云端」——用户没主动选，就不外发数据。
- 费用展示（本轮 token 数 / 估算花费）还没做，列进待办。
