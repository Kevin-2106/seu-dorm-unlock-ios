import SwiftUI

/// 开门方式: 蓝牙缓存、(后续) NFC 行为。
struct OpenMethodSettingsView: View {
    @ObservedObject var nfc: DoorNFCManager
    @ObservedObject private var settings = SettingsManager.shared
    @State private var cleared = false

    var body: some View {
        Form {
            Section {
                Picker("默认方式", selection: Binding(
                    get: { settings.primaryMethod },
                    set: { settings.primaryMethod = $0 })) {
                    ForEach(UnlockMethod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!nfc.isAvailable)
            } header: {
                Text("默认开门方式")
            } footer: {
                Text(nfc.isAvailable
                     ? "决定首页大按钮、锁屏小组件 / 控制、快捷指令「开门」用哪种方式；另一种方式会缩小放在首页底部，随时可点。默认蓝牙。"
                     : "此设备或当前安装方式没有 NFC 权限，只能用蓝牙。")
            }

            Section {
                Toggle("打开 App 时自动 NFC 扫描", isOn: Binding(
                    get: { settings.autoNFC },
                    set: { on in
                        settings.autoNFC = on
                        // 关掉时立刻停掉正在进行的监听，不然要等下次打开 App 才生效
                        if !on { nfc.stopAutoScanning() }
                    }))
            } header: {
                Text("NFC")
            } footer: {
                Text("开启后，打开 App 或回到前台会自动弹出系统的 NFC 扫描面板，碰锁即开。只用蓝牙的话可以关掉(关闭会立刻停止当前监听)；关闭后首页仍可手动点 NFC 开门。在系统面板上点「取消」后，本次不会再自动弹出。")
            }

            Section {
                HStack {
                    Text("蓝牙外设缓存")
                    Spacer()
                    Text(settings.cachedPeripheralID.isEmpty ? "无" : "已缓存").foregroundStyle(.secondary)
                }
                Button("重置蓝牙缓存") {
                    settings.cachedPeripheralID = ""
                    cleared = true
                }
                .disabled(settings.cachedPeripheralID.isEmpty && !cleared)
            } header: {
                Text("蓝牙")
            } footer: {
                Text("第一次开门成功后会记住锁的蓝牙标识，之后跳过扫描直接连接，更快。换了锁或连不上时可以重置，下次会重新扫描。")
            }
        }
        .navigationTitle("开门方式")
        .navigationBarTitleDisplayMode(.inline)
    }
}
