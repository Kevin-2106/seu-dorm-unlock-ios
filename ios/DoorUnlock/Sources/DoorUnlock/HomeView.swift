import SwiftUI

/// 首页：只留"开门"这一件事，参数配置/日志都挪到设置页。
/// iOS 26+ 用 Liquid Glass 材质 (glassEffect/.glassProminent)，更低版本 (iPhone 7 封顶 iOS15)
/// 退回常规的 Material/borderedProminent，两边都能编译、都能用。
/// 背景支持自定义图片 (设置页选)，没设就用深色渐变兜底。
struct HomeView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager
    @ObservedObject private var s = SettingsManager.shared
    @ObservedObject private var background = BackgroundImageStore.shared
    @State private var showSettings = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            backgroundLayer

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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // ─── 背景: 自定义图片(带暗角遮罩方便看清文字) 或 默认深色渐变 ───
    private var backgroundLayer: some View {
        ZStack {
            if let img = background.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.35), .black.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            } else {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.12), Color(red: 0.1, green: 0.13, blue: 0.22)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .clipped()
    }

    // ─── 当前门锁摘要 ───
    private var deviceSummary: some View {
        VStack(spacing: 4) {
            Text(s.deviceId == 0 ? "未配置门锁" : "XN-\(s.deviceId)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            if !s.isConfigured() {
                Text("请先去设置页登录拉取凭证").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // ─── 中心开门大按钮 (带呼吸光晕) ───
    private var unlockButton: some View {
        let busy = ble.state == .scanning || ble.state == .connecting || ble.state == .unlocking
        return ZStack {
            Circle()
                .fill(buttonTint.opacity(0.35))
                .frame(width: pulse ? 220 : 190, height: pulse ? 220 : 190)
                .blur(radius: 24)
                .opacity(busy ? 0.9 : 0.5)

            Group {
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
        .frame(width: 220, height: 220)
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
                .foregroundStyle(nfc.isScanning ? .green : .white.opacity(0.5))
            Text(nfc.isScanning ? "NFC 持续监听中，碰锁即开" : nfc.statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
