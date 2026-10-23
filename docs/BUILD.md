# 构建与发布

← [返回 README](../README.md)

**不需要本地 Xcode。** 整个构建在 GitHub Actions 的 macOS runner 上完成（工作流：`.github/workflows/ios.yml`）。

## 目录

- [触发方式](#触发方式)
- [构建流程](#构建流程)
- [签名：为什么构建期不签、构建后再签](#签名为什么构建期不签构建后再签)
- [版本号与构建号](#版本号与构建号)
- [发布 Release](#发布-release)
- [目录结构](#目录结构)

---

## 触发方式

- **手动**：Actions 页面 → `Build iOS (ad-hoc signed ipa)` → Run workflow。产物在该次运行的 Artifacts 里。
- **打 tag**：推送形如 `v1.0.0` 的 tag，会构建并自动创建 Release，把 `.ipa` 挂上去。见[发布 Release](#发布-release)。

不会因为普通的 push 自动构建——macOS runner 比较贵，所以只手动或打 tag 触发。

---

## 构建流程

0. **协议层单元测试**：`swift test` 跑 `Tests/CryptoTests`，期望值是上游 Kotlin 实现的测试向量，Swift 移植必须逐字节一致。本地也可以在 `ios/DoorUnlock` 下直接运行。
1. **选最新的 Xcode**：runner 上装了多个版本，选编号最大的。XcodeGen 生成的工程格式可能比默认 Xcode 新。
2. **XcodeGen 生成工程**：由 `ios/DoorUnlock/project.yml` 生成 `.xcodeproj`，不把工程文件提交进仓库。
3. **`xcodebuild` 构建**：真机架构（`arm64`），**不签名**。
4. **`codesign` 手动签名**：见下一节。
5. **打包成 `.ipa`**：把 `.app` 放进 `Payload/` 再压缩。
6. **上传产物**。

---

## 签名：为什么构建期不签、构建后再签

**ad-hoc 签名**（`codesign -s -`）不需要开发者账号和证书，但会把 entitlements 正确地嵌进代码签名里。这对 TrollStore 这类工具很关键——它们绕过的是签名的**密码学校验**，签名里**声明**的 entitlements（比如 NFC）仍然会被系统解析并生效。完全不签名的话，就没有地方放 entitlements。

但是 `xcodebuild` 在新版 SDK 上拒绝构建期的 ad-hoc 签名：

```
error: Ad Hoc code signing is not allowed with SDK 'iOS 18.2'
```

所以流程是：构建期 `CODE_SIGNING_ALLOWED=NO`，构建完**单独用 `codesign` 命令行工具**签名（这条路径不受上面那个限制）。

**由内向外签**：

```bash
# 1. 先签小组件扩展 —— 不带 NFC entitlement
codesign --force --sign - MyApp.app/PlugIns/DoorUnlockWidget.appex
# 2. 再签主 App，并嵌入 NFC entitlement
codesign --force --sign - --entitlements Sources/DoorUnlock.entitlements MyApp.app
```

**不要用 `--deep`**：它会把同一份 entitlements 套到嵌套的扩展上。

CI 日志里会打印签名里实际的 entitlements、`PlugIns` 目录内容和 `codesign --verify` 的结果，方便确认。

> 产物**没有**经过苹果签名，也不会被 App Store 接受。它只适合用 TrollStore / SideStore 这类工具安装。

---

## 版本号与构建号

| 字段 | 来源 |
|---|---|
| `CFBundleShortVersionString`（版本） | 打 tag 时取 tag（去掉 `v`）；手动触发时是 `1.0` |
| `CFBundleVersion`（构建号） | 构建时的 UTC 时间戳 `YYMMDDHHmm`（例 `2610241530`），单调递增，避免侧载工具嫌新版构建号更小 |
| `BuildCommit` | `git rev-parse --short HEAD` |

App 首页底部和「设置 → 关于」会显示 `v1.0 (build N · commit)`，用来确认装上的是哪一版。扩展的版本号和主 App 保持一致（系统要求）。

---

## 发布 Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Actions 会构建，并把 `.ipa` 作为附件创建 Release。Release 里的 `.ipa` 是 ad-hoc 签名的，安装方式见 [INSTALL.md](INSTALL.md)。

---

## SideStore 源

打 tag 发布时，CI 会把新版本写进 `source` 分支上的 `apps.json`（AltStore 格式，脚本是 `scripts/make_source.py`），保留历史版本。SideStore 用户添加

```
https://raw.githubusercontent.com/Kevin-2106/seu-dorm-unlock-ios/source/apps.json
```

就能直接安装并收到更新提示。放在单独分支，是为了不污染 `main` 的提交历史。

---

## 国内加速源

同样在发布时，CI 把 ipa 提交到 `cdn` 分支，并生成 `apps-gcore.json` / `apps-cf.json` / `apps-fastly.json` 三份源（分别指向 `gcore.jsdelivr.net` / `testingcf.jsdelivr.net` / `fastly.jsdelivr.net`）。ipa 的下载地址固定到 commit 哈希，源文件按分支访问，发布后主动 purge jsDelivr 缓存。`cdn` 分支会随版本数线性增长（每版约 1.4MB），不做历史改写。

---

## 目录结构

```
.github/workflows/ios.yml     构建 / 签名 / 发布
ios/DoorUnlock/
  Package.swift               仅供 swift test 使用，不参与 App 构建
  Tests/CryptoTests/          协议层单元测试
  project.yml                 XcodeGen 配置：主 App 与小组件扩展两个 target
  Sources/
    DoorUnlock/               主 App 的 Swift 源码
    Widget/                   小组件扩展（锁屏小组件、锁屏控制）
    DoorUnlock.entitlements   NFC entitlement
scripts/make_source.py        生成 SideStore 源
docs/                         这些文档
```

主 App 源码里几个主要的文件：

| 文件 | 职责 |
|---|---|
| `Crypto.swift` | 协议层：CRC8、RC4、设备密钥派生、BLE / NFC 帧的构造与解析 |
| `DoorBLEManager.swift` | CoreBluetooth 状态机，含自动刷新凭据 |
| `DoorNFCManager.swift` | CoreNFC 读卡会话，含持续监听 |
| `ServerApi.swift` | 登录、拉取凭据 |
| `SettingsManager.swift` | 参数持久化（密码走 Keychain） |
| `ConfigCode.swift` | 配置码编码 / 解码 |
| `OpenDoorIntent.swift` | 快捷指令「开门」动作 |
| `HomeView.swift` / `SettingsView.swift` / `TuningView.swift` | 界面 |
| `Effects.swift` / `Tuning.swift` | 视觉效果、触感、可调参数 |
