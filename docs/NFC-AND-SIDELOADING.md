# 为什么侧载通常用不了 NFC，TrollStore / 越狱却可以

← [返回 README](../README.md)

这是实测过的现象，也是整个项目里最容易让人困惑的一点：同一个 `.ipa`，用 SideStore 装上后提示"暂不支持 NFC 读卡"，用 TrollStore 装在 iPhone 7 上却能读卡开门。

## 结论

| 安装方式 | 蓝牙 | NFC | 说明 |
|---|---|---|---|
| TrollStore | ✅ | ✅ | iPhone 7（iOS 15）实测 NFC 可用 |
| 越狱 + 伪签名 | ✅ | ✅（原理上） | 未单独测试 |
| 付费开发者账号 | ✅ | ✅（原理上） | 需在 App ID 上开启 NFC Tag Reading，未测试 |
| SideStore / AltStore / Sideloadly + 免费 Apple ID | ✅ | ❌ | 实测：显示"暂不支持 NFC 读卡" |
| LiveContainer | ✅ | ❌ | 实测：同上 |

**蓝牙不受这个限制**：它只需要 Info.plist 里的用途说明字符串，不需要特殊 entitlement，所以任何方式装上都能开门。

## 原理

### 1. NFC 读这把锁需要一个 entitlement

这把锁的 NFC 感应区是 ISO 14443-A 的 Type 2 标签，开门协议（`0xB1` 帧）是对它发**原始帧**，不是标准 NDEF 读写。iOS 上做这件事要用 CoreNFC 的 `NFCTagReaderSession`，并且 App 的代码签名里必须带有：

```
com.apple.developer.nfc.readersession.formats
```

没有它，`NFCTagReaderSession.readingAvailable` 返回 `false`，App 里就表现为"此设备不支持 NFC 读卡"——**和硬件是否支持无关**。iPhone 15 一样会这样。

### 2. 正常情况下，entitlement 要由苹果"授权"

iOS 校验一个 App 的 entitlement 时，要求它被一份**苹果签发的 provisioning profile** 授权。profile 是在 Apple Developer 后台根据你的 App ID 生成的，而 **"NFC Tag Reading" 这项能力只对付费开发者账号（$99/年）开放**，免费的 Personal Team 勾选不了。

### 3. 各种安装方式的区别

**SideStore / AltStore / Sideloadly（免费 Apple ID）**

它们本质上是"帮你用自己的 Apple ID 去苹果申请 profile，然后给 App 重签名"。免费账号申请不到 NFC 能力，生成的 profile 里就没有这一条，重签出来的 App 签名里自然没有 NFC entitlement。工程里写再多 entitlement 声明也没用——是苹果服务器那一步没给。

**TrollStore**

利用 CoreTrust 的签名校验漏洞：系统会把"任意伪造的签名"当作有效。此时 App 的 entitlement 直接取自二进制自带的签名，**不再需要苹果签发的 profile 来授权**，想声明什么就是什么。所以只要 `.ipa` 里嵌入了 NFC entitlement（本项目的 CI 构建时用 `codesign -s -` 嵌入），安装后就能读卡。

代价是它依赖这个漏洞，因此**只适用于特定的 iOS 版本区间**，具体以 [TrollStore 官方说明](https://github.com/opa334/TrollStore)为准。

**越狱**

越狱通常会放宽或补丁系统的代码签名校验（AMFI），用 `ldid -S` 之类的方式给二进制写入伪签名和 entitlement 即可，原理和 TrollStore 类似。本项目没有单独在越狱环境测试。

**LiveContainer**

被"寄生"的 App 运行在宿主 LiveContainer 的进程里，只能使用**宿主自己签名里的** entitlement，宿主没有 NFC 就没有。

### 4. 本项目是怎么嵌入 entitlement 的

`xcodebuild` 在新版 SDK 上不允许构建期使用 ad-hoc 签名（`Ad Hoc code signing is not allowed with SDK`），所以流程是：

1. 构建期完全不签名；
2. 构建完再用 `codesign` 命令行工具**由内向外**签名：先签小组件扩展（不带 NFC entitlement），再签主 App 并嵌入 `Sources/DoorUnlock.entitlements`；
3. 打包成 `.ipa`。

细节见 [BUILD.md](BUILD.md)。

## 如果你想要 NFC，但不想用 TrollStore

- **付费开发者账号**：在 App ID 上开启 NFC Tag Reading，用 Xcode 或其他方式签名安装。原理上可行，本项目没有测试。
- **只用蓝牙**：功能上没有损失，开门流程一样，只是少了"贴近就开"。配合[锁屏小组件 / Action 按钮](USAGE.md)，日常使用差距不大。

## 还有一件事：NFC 在 iOS 上怎么用也和 Android 不同

即使 NFC 权限齐了，iOS 也**做不到** Android 那种"锁屏状态碰一下直接打开 App"，见 [VS-ANDROID.md](VS-ANDROID.md#ios-上做不到或不同的)。
