import SwiftUI

/// 设置首页: 只放分类入口，具体内容都在子页面里。
/// 子页面: LockSettingsView(门锁) / OpenMethodSettingsView(开门方式) /
/// AppearanceSettingsView(外观与反馈) / DiagnosticsView(诊断) / AboutView(关于)。
struct SettingsView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink { LockSettingsView() } label: {
                        row("门锁", icon: "lock.fill", detail: lockSummary)
                    }
                    NavigationLink { OpenMethodSettingsView(nfc: nfc) } label: {
                        row("开门方式", icon: "antenna.radiowaves.left.and.right", detail: "")
                    }
                    NavigationLink { AppearanceSettingsView() } label: {
                        row("外观与反馈", icon: "paintbrush.fill", detail: "")
                    }
                }
                Section {
                    NavigationLink { UnlockHistoryView() } label: {
                        row("开锁记录", icon: "clock.arrow.circlepath", detail: "")
                    }
                    NavigationLink { DiagnosticsView(ble: ble, nfc: nfc) } label: {
                        row("诊断", icon: "stethoscope", detail: "")
                    }
                    NavigationLink { AboutView() } label: {
                        row("关于", icon: "info.circle", detail: BuildInfo.version)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var lockSummary: String {
        settings.isConfigured() ? "XN-" + String(settings.deviceId) : "未配置"
    }

    private func row(_ title: String, icon: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if !detail.isEmpty {
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
