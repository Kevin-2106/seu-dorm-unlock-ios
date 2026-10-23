import SwiftUI

/// 开门方式: 蓝牙缓存、(后续) NFC 行为。
struct OpenMethodSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var cleared = false

    var body: some View {
        Form {
            Section {
                Toggle("打开 App 时自动 NFC 扫描", isOn: Binding(
                    get: { settings.autoNFC },
                    set: { settings.autoNFC = $0 }))
            } header: {
                Text("NFC")
            } footer: {
                Text("开启后，打开 App 或回到前台会自动弹出系统的 NFC 扫描面板，碰锁即开。只用蓝牙的话可以关掉；关闭后首页仍有按钮可以手动开始 NFC 扫描。")
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
