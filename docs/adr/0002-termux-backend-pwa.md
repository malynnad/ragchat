# 架构采用 Termux 小后端 + PWA 前端，数据存手机文件

> **状态：superseded by ADR-0004**（2026-11-14，项目转向 RAG 知识库后重新选型，用户选择 Flutter + nobodywho 原生路线）。

聊天程序只在手机浏览器使用。页面本来就需要 HTTP 服务托管（Android 上 file:// 打开本地 HTML 限制很多），因此选择 Termux 里跑一个轻量后端（托管页面、转发 Ollama 请求、记忆与聊天记录存为手机文件），而非纯前端 + 浏览器存储：两者部署成本几乎相同，但后端方案清浏览器缓存不丢数据，记忆提取可在后台执行。前端做成 PWA，安装到桌面点图标启动。

## 备选方案

- **纯前端 + localStorage/IndexedDB**：需配置 Ollama 跨域；记忆提取只在页面打开时运行（下次打开补提）；清浏览器数据会丢记忆。被否决。

## 后果

- Termux 需保持常驻（wake lock + 电池优化白名单），否则后端与 Ollama 被系统杀掉，PWA 无法连接。
- PWA 安装依赖 localhost 安全上下文；须通过 http://localhost:端口 访问，用局域网 IP 的纯 HTTP 访问无法安装（本机使用场景不受影响）。