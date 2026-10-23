import SwiftUI

/// app 根视图：免责声明门禁 + 持有 BLE/NFC 状态对象，往下传给 HomeView/SettingsView。
/// 页面内容本身拆到 HomeView (首页，开门按钮) 和 SettingsView (账号/参数/日志)。
struct ContentView: View {
    @StateObject private var ble = DoorBLEManager()
    @StateObject private var nfc = DoorNFCManager()
    @AppStorage("agreed_disclaimer") private var agreedDisclaimer = false
    @Environment(\.scenePhase) private var scenePhase
    /// 由小组件/控制唤起时置位：此时要直接走蓝牙开门，不再弹 NFC 系统面板抢屏幕
    @State private var suppressAutoNFC = false

    var body: some View {
        if !agreedDisclaimer {
            disclaimerView
        } else {
            HomeView(ble: ble, nfc: nfc)
            .onOpenURL { url in handleOpenURL(url) }
            .onReceive(NotificationCenter.default.publisher(for: .doorUnlockRequested)) { _ in
                UnlockRequest.pending = false
                startExternalUnlock()
            }
            .onAppear {
                // 冷启动: App Intent 的 perform 可能先于界面创建，通知已丢，靠标记补上
                if UnlockRequest.pending {
                    UnlockRequest.pending = false
                    startExternalUnlock()
                }
                startAutoNFCIfPossible()
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    startAutoNFCIfPossible()
                case .background:
                    suppressAutoNFC = false
                    // 真正退到后台才停：NFC 系统弹窗("请贴近")会让 scenePhase 短暂变成
                    // .inactive，不是真的离开 app，那种瞬时状态不处理，否则会跟弹窗自己的
                    // 生命周期打架，把刚开的会话又取消掉。
                    nfc.stopAutoScanning()
                default:
                    break
                }
            }
        }
    }

    private var disclaimerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("免责声明").font(.title2).bold()
            Text("""
            本应用为个人学习与自用目的、基于公开信息对"住理生活"门锁通讯协议的逆向移植，\
            仅用于使用你自己账号换取的凭证开启你自己绑定的门锁。

            不提供、不包含任何绕过他人账号鉴权或批量开锁的功能。\
            使用本应用产生的一切后果由使用者自行承担。
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            Button("我已阅读并同意") { agreedDisclaimer = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    /// 锁屏小组件 / 锁屏控制点按后经 doorunlock://unlock 唤起：立即开始蓝牙开门。
    /// 冷启动时 onAppear 可能先于 onOpenURL 已经把 NFC 会话开起来了，所以这里要主动停掉，
    /// 并置位 suppressAutoNFC 防止 onOpenURL 先到、onAppear 后到时又把它开起来。
    private func handleOpenURL(_ url: URL) {
        guard url.scheme == "doorunlock", url.host == "unlock" else { return }
        startExternalUnlock()
    }

    /// 外部触发开门的统一入口 (小组件 URL / 快捷指令 App Intent / Action 按钮 / Siri)。
    private func startExternalUnlock() {
        suppressAutoNFC = true
        nfc.stopAutoScanning()
        let s = SettingsManager.shared
        guard s.isConfigured(), s.deviceId != 0 else { return }
        guard ble.state != .scanning, ble.state != .connecting, ble.state != .unlocking else { return }
        Task { await ble.unlock() }
    }

    /// app 一打开(或从后台回来)就自动进入 NFC 持续监听模式，
    /// 不用再手动点按钮——前提是已经配置好凭证。
    private func startAutoNFCIfPossible() {
        guard agreedDisclaimer, nfc.isAvailable, !nfc.isScanning, !suppressAutoNFC else { return }
        let s = SettingsManager.shared
        guard s.isConfigured(), s.deviceId != 0 else { return }
        nfc.startUnlock(auto: true)
    }
}

#Preview {
    ContentView()
}
