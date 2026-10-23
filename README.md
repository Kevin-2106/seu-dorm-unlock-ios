# 门钥 (iOS)

「住理生活」门锁系统的**非官方 iOS 客户端**：用**你自己的账号**登录，换取**你自己绑定的门锁**的开门凭据，通过蓝牙 / NFC 开门。

> 与武汉辛纳电子科技、「住理生活」官方 App 没有任何关联，也不使用其名称、图标或素材。

## 这是什么 / 不是什么

本项目基于 [Haa1024/SEU-Door-Unlock](https://github.com/Haa1024/SEU-Door-Unlock)（MIT）对门锁通讯协议的逆向成果。上游是 Android 应用；这里是**用 Swift 重新实现的 iOS 版本**。

- ✅ 协议层（加密、帧格式、BLE / NFC 开门流程）是对上游 Kotlin 实现的**移植**，并用独立的 Kotlin / Swift 工具链生成测试向量做过字节级比对。
- ⚠️ **不是完整复现**：只移植了"登录 → 取凭据 → 开门"这条主路径，下面列了哪些没做。
- ⚠️ **界面是独立设计的**，没有沿用上游的界面和配色。

### 移植了什么

| 功能 | 状态 |
|---|---|
| BLE 开门（`0x74` / `0x75` / `0x78`） | ✅ 真机验证通过 |
| NFC 开门（`0xB1`，`NFCMiFareTag` 裸帧） | ✅ 真机验证通过（需要 NFC entitlement，见下） |
| 手机号 + 密码登录、拉取门锁凭据 | ✅ 真机验证通过 |
| 密钥轮换（NFC 每次开门后保存锁返回的新 chainKey） | ✅ |
| 自动刷新凭据（锁返回 `25`/`24` 时从服务器重取并重试；`27` 时向锁索取新钥匙） | ⚠️ 逻辑已移植、可编译，**未经真机验证** |
| NFC 路径的自动刷新 | ❌ 上游也没有 |

### 没有移植的

- 支付宝一键登录
- NFC 磁贴写卡 / 磁贴触发开门
- 读取 NDEF / 用标签 UID 反推设备号（诊断用途）
- 旧的"在线重置离线计数器"方案（上游已标注废弃）
- 上游的"占用官方包名"变体及相关内容

### iOS 版新增的

- 同一账号多台设备共用的**配置码**（只含开门凭据，不含账号密码）
- 蓝牙外设 UUID 缓存直连，跳过广播扫描
- 打开 App 即进入 NFC 持续监听
- 锁屏 / 主屏小组件、iOS 18 锁屏控制、快捷指令「开门」动作
- 首页：iOS 26 Liquid Glass 适配、陀螺仪视差、CoreHaptics 触感、可调参数页

## 平台限制（不是 bug）

- **碰一下锁屏自动弹出打开 App 做不到**：Android 版靠"后台 NFC 分发"，iOS 的 Background Tag Reading 只在 iPhone XS 及以上可用，且打开哪个 App 由标签里 URL 所属域名的 Universal Link 决定，无法让系统打开别人的 App 以外的应用。
- **NFC 需要 `com.apple.developer.nfc.readersession.formats` entitlement**：付费开发者账号、或 TrollStore 这类不依赖苹果签发 profile 的方式可以；**免费 Apple ID 通过 SideStore 侧载拿不到这个 entitlement**，NFC 不可用，蓝牙不受影响。
- **免费 Apple ID 有 App ID 配额（10 个 / 滚动 7 天）**，小组件扩展会多占 1 个；扩展被移除时，用"快捷指令 → 开门"也能把入口放到锁屏。

## 使用

1. 设置页输入手机号密码 →「登录并拉取门锁凭证」（会把官方 App 的会话顶下线，这是服务端的单点登录行为）。
2. 回首页点「开门」；或 App 在前台时直接把手机贴近门锁感应区。
3. 其他设备：在已配置的设备上「导出配置码」，在新设备「从剪贴板导入」。

> 配置码的注意事项：NFC 每次开门锁都会更换 chainKey，旧的随之失效。两台设备共用同一份配置码、其中一台用 NFC 开过门后，另一台手里的就可能是旧钥匙，需要登录一次重新拉取。（这是对协议行为的推断，尚未验证。）

## 构建

不需要本地 Xcode。GitHub Actions 的 macOS runner 构建（`.github/workflows/ios.yml`，手动触发）：

- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 根据 `ios/DoorUnlock/project.yml` 生成工程
- 构建期不签名，随后用 `codesign -s -` 做 ad-hoc 签名并嵌入 NFC entitlement（xcodebuild 在新 SDK 上不允许构建期 ad-hoc 签名）
- 产物是 ad-hoc 签名的 `.ipa`，用 TrollStore / SideStore 等自行安装

构建号 = Actions 运行编号，commit 短哈希显示在首页底部和设置页「关于」，用来确认装上的是哪一版。

## 免责声明

仅供学习研究蓝牙低功耗 / NFC 通信协议使用。只应使用**你自己账号**换取的凭据，开启**你有合法使用权**的门锁；本项目不提供、也不会加入任何绕过他人账号鉴权、批量或通用开锁的功能。因使用本软件产生的一切后果由使用者自行承担。所有数据只保存在设备本地，不会上传到第三方。

## 致谢与许可

- 协议逆向成果与 Android 实现：[Haa1024/SEU-Door-Unlock](https://github.com/Haa1024/SEU-Door-Unlock)，MIT。
- 本项目同样以 MIT 发布，保留上游的版权与许可声明，见 [LICENSE](../LICENSE)。
