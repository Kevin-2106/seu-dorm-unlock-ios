# 安装说明

← [返回 README](../README.md)

## 目录

- [选哪个侧载工具](#选哪个侧载工具)
- [TrollStore](#trollstore)
- [SideStore（免费 Apple ID）](#sidestore免费-apple-id)
- [小组件扩展没装上](#小组件扩展没装上)
- [确认装对了](#确认装对了)
- [常见问题](#常见问题)

---

## 选哪个侧载工具

本项目发布的是 **ad-hoc 签名的 `.ipa`**，没有经过 App Store，需要用侧载工具安装。

| | TrollStore | SideStore（免费 Apple ID） |
|---|---|---|
| 蓝牙开门 | ✅ | ✅ |
| NFC 开门 | ✅ | ❌ |
| 锁屏小组件 / 控制 | ✅（系统版本够新时） | ✅（需要额外 1 个 App ID 名额） |
| 快捷指令「开门」 | ✅ | ✅ |
| 签名有效期 | 永久 | 7 天 |
| 对 iOS 版本的要求 | 仅限特定版本 | 大多数版本 |
| 官方教程 | [安装教程](https://ios.cfw.guide/installing-trollstore/) · [项目主页](https://github.com/opa334/TrollStore) | [文档](https://docs.sidestore.io/) · [安装前准备](https://docs.sidestore.io/docs/installation/prerequisites) · [项目主页](https://github.com/SideStore/SideStore) |

**如果你要用 NFC**：只能选 TrollStore（或越狱、付费开发者账号）。原因见 [NFC-AND-SIDELOADING.md](NFC-AND-SIDELOADING.md)。

**如果只用蓝牙 + 锁屏入口**：SideStore 就够了，不需要越狱。

> 这两个工具各自的安装步骤在官方文档里写得最准，也会随 iOS 版本变化，所以这里**不重复**，请直接按上表的官方教程准备环境。

---

## TrollStore

1. 按[官方教程](https://ios.cfw.guide/installing-trollstore/)确认你的 iOS 版本是否受支持，并安装 TrollStore。
2. 从本仓库的 [Releases](../../../releases) 下载 `.ipa`。
3. 用 TrollStore 安装这个 `.ipa`（TrollStore 内的「安装」入口，或在「文件」/ Safari 里选择用 TrollStore 打开）。
4. 桌面出现「门钥」即安装完成。

TrollStore 装的 App 签名永久有效，不用刷新。

---

## SideStore（免费 Apple ID）

1. 按[官方文档](https://docs.sidestore.io/)准备并安装 SideStore。
2. 从本仓库的 [Releases](../../../releases) 下载 `.ipa`。
3. 在 SideStore 里添加这个 `.ipa` 安装。

   **或者添加源（推荐）**：SideStore → 「源」→ 右上角 `+`，填入
   ```
   https://raw.githubusercontent.com/Kevin-2106/seu-dorm-unlock-ios/source/apps.json
   ```
   之后在源里直接安装「门钥」，有新版本时会收到更新提示。源由 CI 在发布 Release 时自动更新。
4. 桌面出现「门钥」即安装完成。

注意事项：

- **签名 7 天过期**，需要刷新。SideStore 支持自动刷新，具体见其文档。
- **免费账号的 App ID 配额：滚动 7 天内最多 10 个。** 这个额度是**整个 Apple ID 共用**的：SideStore 自己、其他侧载的 App、以及它们各自的扩展都会占用。**删除 App 不会释放名额**，要等它自然过期。
- **NFC 不可用**：免费账号申请不到 NFC 所需的权限，首页会提示"此设备不支持 NFC 读卡"。蓝牙不受影响。

---

## 小组件扩展没装上

「门钥」由两部分组成：主 App（`io.github.kevin-2106.doorkey`）和小组件扩展（`io.github.kevin-2106.doorkey.widget`）。每个都要占一个 App ID。

**症状**：安装时 SideStore 提示 App ID 数量已满，让你选择"移除 app extension"；选了之后，锁屏小组件、锁屏控制就都没有了。

**确认**：打开「门钥」→ 设置 →「关于」，看"小组件扩展"是"已安装"还是"未安装"。

**怎么办**（三选一）：

1. **直接用快捷指令「开门」**：它在主 App 里，不依赖扩展，不占额外 App ID。绑定 Action 按钮或放到锁屏的快捷指令控件，效果几乎一样。见 [USAGE.md](USAGE.md#入口-3action-按钮与快捷指令)。
2. **等名额释放**：每个 App ID 注册后 7 天过期，在 SideStore 设置里能看到各 ID 的到期时间。到期后重新安装、这次**不要**选"移除 app extension"。
3. **付费开发者账号**：App ID 额度远大于免费账号。

---

## 确认装对了

装完后看两个地方：

- **首页最底部**一行淡淡的字，形如 `v1.1.0 (build 2610251530 · a1b2c3d)`：版本、构建号（构建时的 UTC 时间 `YYMMDDHHmm`）、commit 短哈希。和 Releases 页对一下就知道装的是不是最新。
- **设置 →「关于」**：同样的版本信息，再加"小组件扩展：已安装 / 未安装"。

---

## 从 v1.1.0 及更早版本升级（包名变更）

v1.2.0 起包名由 `com.selfuse.doorunlock` 改为 `io.github.kevin-2106.doorkey`。系统会把它当成**全新的 App**：

- 旧的「门钥」不会被覆盖，需要自己删除；旧版的凭据、设置、Keychain 里的密码**不会带过来**，新版里重新登录一次即可；
- 锁屏小组件、控制要重新添加，快捷指令里的「开门」动作要重新选；
- 免费 Apple ID 会多占 2 个 App ID 名额（主 App + 小组件），旧的要等它们 7 天后自然过期才释放。

---

## 常见问题

**装好后蓝牙开不了门，提示"蓝牙未开启"？**
到系统设置里给「门钥」打开蓝牙权限，并确认系统蓝牙开关是开的。

**登录后官方「住理生活」被顶下线了？**
这是服务端的单点登录行为，登录一次就会让别处的会话失效。拉取一次凭据之后，日常开门不需要再登录。

**NFC 一直提示不支持？**
见 [NFC-AND-SIDELOADING.md](NFC-AND-SIDELOADING.md)。免费账号 + SideStore 是装不出 NFC 权限的。

**iPhone 7 上没有小组件？**
锁屏小组件的系统下限是 iOS 16，iPhone 7 最高到 iOS 15，所以没有。App 本体（蓝牙、NFC）可以正常使用。
