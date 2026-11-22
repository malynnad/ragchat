# 发版清单

以发 `1.2.0`（构建号 `+4`）为例。步骤按顺序做，**第 7 步复核别省**。

## 0. 构建前：别乱 clean

- **平时不要 `flutter clean`**：增量构建 40–90 秒，clean 之后 3–5 分钟起步。
- `app/build/nobodywho/nobodywho-cache/` 里是插件用 Dart 脚本从 GitHub 下的预编译库：
  arm64 的 `libnobodywho_flutter.so` 正常 **约 109 MB**。删了要重新下 100 MB+，网络差会被截断。
- 构建前扫一眼，太小就别构建：

```bash
ls -lh app/build/nobodywho/nobodywho-cache/nobodywho/6.0.0/android-arm64-v8a/libnobodywho_flutter.so
# 正常 ~109M；如果只有十几兆，说明下载被截断了
```

被截断时不用重新下载：从上一版能用的 APK 里解出来覆盖，再构建：

```bash
unzip -p ~/Downloads/RAGchat-<上一版>-arm64.apk lib/arm64-v8a/libnobodywho_flutter.so \
  > app/build/nobodywho/nobodywho-cache/nobodywho/6.0.0/android-arm64-v8a/libnobodywho_flutter.so
```

## 1. 定版本号

- `app/pubspec.yaml`：`version: 1.2.0+4`
- **公开发过的号不能覆写**：修 bug → `1.0.1`；功能 → `1.2.0`；构建号（`+`）每次都要涨。
- 新建 `docs/release-notes-v1.2.0.md`（旧版说明留着）。

## 2. 测试

```bash
cd app
flutter test
```

## 3. 构建（只出 arm64）

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```

- `--target-platform android-arm64` 跳过 x86_64 / armeabi，少下一个 81 MB 的库，也少一份 APK。
- 产物：`app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，正常 **约 45 MB**。

构建完先验一下原生库没被截断：

```bash
unzip -l app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | grep libnobodywho
# 未压缩大小应 > 100 MB；APK 总大小 45 MB 左右。明显偏小就是库坏了
```

## 4. 出包、算校验值、验签

```bash
cp app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ~/Downloads/RAGchat-1.2.0-arm64.apk
shasum -a 256 ~/Downloads/RAGchat-1.2.0-arm64.apk
stat -f%z ~/Downloads/RAGchat-1.2.0-arm64.apk
~/Library/Android/sdk/build-tools/<版本>/apksigner verify --print-certs ~/Downloads/RAGchat-1.2.0-arm64.apk
```

把 sha256、字节数、证书指纹填进 `release-notes-v1.2.0.md` 的「校验」段。

## 5. 提交并打 tag

```bash
git add -A
git commit -m "release: 1.2.0"

git tag -a v1.2.0 -m "RAGchat 1.2.0（正式签名）"

git push gitee main
git push gitcode main
git push gitee v1.2.0
git push gitcode v1.2.0
```

## 6. 移动已有 tag（只在「还没发过」时用）

```bash
git tag -d v1.2.0
git tag -a v1.2.0 -m "RAGchat 1.2.0（正式签名）"
git push gitee :refs/tags/v1.2.0   # 先删远端
git push gitcode :refs/tags/v1.2.0
git push gitee v1.2.0              # 再推
git push gitcode v1.2.0
```

**已经发布过的版本不要再移 tag**，直接升版本号。

## 7. 平台上建 Release

两边一样：选 tag `v1.2.0` → 标题 `RAGchat 1.2.0` → 粘贴 release notes → 上传 `RAGchat-1.2.0-arm64.apk` → **等上传进度走完** → 点发布（别存草稿）。

## 8. 复核（发完必做）

```bash
# Gitee：发行版 + 附件
curl -s "https://gitee.com/api/v5/repos/dannylam/ragchat/releases" | python3 -m json.tool | head -40

# GitCode：附件名、大小、sha256
curl -s "https://api.gitcode.com/api/v5/repos/DannyLam/ragchat/releases/tags/v1.2.0" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); [print(a['name'], a['size'], a.get('digest')) for a in d['assets']]"
```

核对：附件大小 = 本地字节数；sha256 = 本地校验值；tag 指向 `git rev-parse v1.2.0`。
