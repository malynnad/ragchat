# 发版清单

以发 `1.1.0`（构建号 `3001`）为例。步骤按顺序做，最后一步是复核，别省。

## 1. 定版本号

- `app/pubspec.yaml`：`version: 1.1.0+3001`
- 版本规则：**只要公开发过就不能覆写同一个号**。修 bug → `1.0.1`；有功能 → `1.1.0`；构建号（`+` 后面）每次都要涨。
- 新建 `docs/release-notes-v1.1.0.md`（旧版说明留着，别改）。

## 2. 测试与构建

```bash
cd app
flutter test
flutter build apk --release --split-per-abi
```

产物：`app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`（只用 arm64 这个）。

## 3. 出包、算校验值、验签

```bash
cp app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ~/Downloads/RAGchat-1.1.0-arm64.apk
shasum -a 256 ~/Downloads/RAGchat-1.1.0-arm64.apk
stat -f%z ~/Downloads/RAGchat-1.1.0-arm64.apk
~/Library/Android/sdk/build-tools/<版本>/apksigner verify --print-certs ~/Downloads/RAGchat-1.1.0-arm64.apk
```

把 sha256、字节数、证书指纹填进 `release-notes-v1.1.0.md` 的「校验」段。

## 4. 提交并打 tag

```bash
git add -A
git commit -m "release: 1.1.0"

# 本地打附注 tag
git tag -a v1.1.0 -m "RAGchat 1.1.0（正式签名）"

# 先推代码
git push gitee main
git push gitcode main

# 再推 tag
git push gitee v1.1.0
git push gitcode v1.1.0
```

## 5. 移动已有 tag（只在「还没发过」时用）

同一个版本号改了代码，需要让 tag 跟着走：

```bash
git tag -d v1.0.0                  # 删本地
git tag -a v1.0.0 -m "RAGchat 1.0.0（正式签名）"
git push gitee :refs/tags/v1.0.0   # 删远端（先删）
git push gitcode :refs/tags/v1.0.0
git push gitee v1.0.0              # 再推
git push gitcode v1.0.0
```

**已经发布过的版本不要再移 tag**，直接升版本号。

## 6. 平台上建 Release

两边操作一样：选 tag `v1.1.0` → 标题 `RAGchat 1.1.0` → 粘贴 release notes → 上传 `RAGchat-1.1.0-arm64.apk` → **等上传进度走完** → 点发布（不要存草稿）。

## 7. 复核（发完必做）

```bash
# Gitee：确认发行版和附件大小
curl -s "https://gitee.com/api/v5/repos/dannylam/ragchat/releases" | python3 -m json.tool | head -40

# GitCode：确认附件名、大小、sha256
curl -s "https://api.gitcode.com/api/v5/repos/DannyLam/ragchat/releases/tags/v1.1.0" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); [print(a['name'], a['size'], a.get('digest')) for a in d['assets']]"
```

对一下：附件大小 = 本地字节数，sha256 = 本地校验值，tag 指向的 commit = `git rev-parse v1.1.0`。
