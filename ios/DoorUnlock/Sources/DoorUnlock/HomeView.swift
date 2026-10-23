import SwiftUI

/// 首页：只留"开门"这一件事，参数配置/日志都挪到设置页。
/// iOS 26+ 用 Liquid Glass 材质 (glassEffect/.glassProminent)，更低版本 (iPhone 7 封顶 iOS15)
/// 退回常规的 Material/borderedProminent，两边都能编译、都能用。
struct HomeView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager
    @State private var showSettings = false

    private let s = SettingsManager.shared

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 28) {
                Spacer()

                deviceSummary

                unlockButton

                statusCard

                Spacer()

                nfcHintRow
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(ble: ble, nfc: nfc)
        }
    }

    // ─── 背景 ───
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.07, blue: 0.12), Color(red: 0.1, green: 0.13, blue: 0.22)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // ─── 当前门锁摘要 ───
    private var deviceSummary: some View {
        VStack(spacing: 4) {
            Text(s.deviceId == 0 ? "未配置门锁" : "XN-\(s.deviceId)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            if !s.isConfigured() {
                Text("请先去设置页登录拉取凭证").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // ─── 中心开门大按钮 ───
    private var unlockButton: some View {
        let busy = ble.state == .scanning || ble.state == .connecting || ble.state == .unlocking
        return Group {
            if #available(iOS 26.0, *) {
                Button {
                    Task { await ble.unlock() }
                } label: {
                    unlockButtonLabel(busy: busy)
                }
                .buttonStyle(.glassProminent)
                .tint(buttonTint)
                .disabled(busy || !s.isConfigured())
            } else {
                Button {
                    Task { await ble.unlock() }
                } label: {
                    unlockButtonLabel(busy: busy)
                        .background(Circle().fill(buttonTint))
                }
                .buttonStyle(.plain)
                .disabled(busy || !s.isConfigured())
            }
        }
        .frame(width: 180, height: 180)
    }

    private func unlockButtonLabel(busy: Bool) -> some View {
        VStack(spacing: 10) {
            if busy {
                ProgressView().tint(.white).scaleEffect(1.4)
            } else {
                Image(systemName: ble.state == .success ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
            }
            Text(busy ? "开门中" : "开门")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: 180, height: 180)
    }

    private var buttonTint: Color {
        switch ble.state {
        case .success: return .green
        case .failed: return .red
        default: return .blue
        }
    }

    // ─── 状态卡片 ───
    private var statusCard: some View {
        Group {
            if #available(iOS 26.0, *) {
                statusCardContent
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            } else {
                statusCardContent
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var statusCardContent: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(buttonTint)
                .frame(width: 10, height: 10)
            Text(ble.statusText)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(16)
    }

    // ─── NFC 持续监听提示条 ───
    private var nfcHintRow: some View {
        HStack(spacing: 8) {
            Image(systemName: nfc.isScanning ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                .foregroundStyle(nfc.isScanning ? .green : .white.opacity(0.4))
            Text(nfc.isScanning ? "NFC 持续监听中，碰锁即开" : nfc.statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
