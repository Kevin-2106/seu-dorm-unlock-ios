import SwiftUI

/// 首页：只留"开门"这一件事，参数配置/日志都挪到设置页。
/// iOS 26+ 用 Liquid Glass 材质，更低版本 (iPhone 7 封顶 iOS15) 退回常规 Material。
///
/// 布局要点 (之前踩过的坑):
/// - 背景必须用 .background { } 挂，不能当 ZStack 兄弟节点: scaledToFill 的图片尺寸
///   比屏幕大，作为兄弟节点会撑大父布局，导致状态卡片被拉到图片宽度、溢出屏幕。
/// - 不套 NavigationView: 首页不需要导航栏，套了会在顶部多出一条不透明的栏，
///   背景铺不到安全区。设置按钮改成固定在安全区内的 overlay。
struct HomeView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager
    @ObservedObject private var s = SettingsManager.shared
    @ObservedObject private var background = BackgroundImageStore.shared
    @StateObject private var motion = MotionManager()
    @AppStorage("button_fill_transparent") private var transparentFill = false

    @State private var showSettings = false
    @State private var pulse = false
    @State private var burst: CGFloat = 0
    @State private var shakes: CGFloat = 0

    private let ticker = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    private var busy: Bool {
        ble.state == .scanning || ble.state == .connecting || ble.state == .unlocking
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            deviceSummary

            unlockCluster

            statusCard

            Spacer()

            nfcHintRow
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundLayer.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            gearButton
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(ble: ble, nfc: nfc)
        }
        .onAppear {
            motion.start()
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear { motion.stop() }
        .onReceive(ticker) { _ in
            if busy { Haptics.tick() }
        }
        .onChange(of: ble.state) { newState in
            switch newState {
            case .scanning:
                Haptics.start()
            case .success:
                Haptics.success()
                playBurst()
            case .failed:
                Haptics.failure()
                withAnimation(.linear(duration: 0.5)) { shakes += 3 }
            default:
                break
            }
        }
        .onChange(of: nfc.statusText) { text in
            if text.hasPrefix("开门成功") || text.hasPrefix("门已打开") {
                Haptics.success()
                playBurst()
            } else if text.hasPrefix("开门失败") || text.hasPrefix("门锁无响应") {
                Haptics.failure()
                withAnimation(.linear(duration: 0.5)) { shakes += 3 }
            }
        }
    }

    private func playBurst() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { burst = 0 }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.9)) { burst = 1 }
        }
    }

    // ─── 背景: 自定义图片(带暗角遮罩+陀螺仪视差) 或 默认深色渐变 ───
    private var backgroundLayer: some View {
        ZStack {
            if let img = background.image {
                // Color.clear 占满提议尺寸，图片只作为 overlay 并被 clipped，
                // 这样图片自身的(更大的)尺寸不会反过来影响布局。
                Color.clear
                    .overlay(
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(1.12)
                            .offset(x: CGFloat(-motion.x) * 14, y: CGFloat(-motion.y) * 14)
                    )
                    .clipped()
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
    }

    // ─── 右上角设置按钮 (固定位置，不是 toolbar) ───
    private var gearButton: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            } else {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
    }

    // ─── 当前门锁摘要 ───
    private var deviceSummary: some View {
        VStack(spacing: 4) {
            // 用 String 而不是直接插值 Int32，避免被格式化成 "2,284,408"
            Text(s.deviceId == 0 ? "未配置门锁" : "XN-" + String(s.deviceId))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            if !s.isConfigured() {
                Text("请先去设置页登录拉取凭证").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // ─── 开门按钮 + 周围的所有特效 ───
    private var unlockCluster: some View {
        ZStack {
            // 呼吸光晕 (待机时缓慢呼吸，随陀螺仪反向漂移)
            Circle()
                .fill(buttonTint.opacity(0.35))
                .frame(width: pulse ? 230 : 195, height: pulse ? 230 : 195)
                .blur(radius: 26)
                .opacity(busy ? 0.95 : 0.55)
                .offset(x: CGFloat(-motion.x) * 12, y: CGFloat(-motion.y) * 12)

            // 待机: 缓慢旋转的渐变光环
            idleRing

            // 搜索中: 向外扩散的涟漪
            if busy { rippleLayer }

            // 成功: 一圈向外炸开的绿环
            if burst > 0 {
                Circle()
                    .stroke(Color.green.opacity(Double(1 - burst)), lineWidth: 6 * (1 - burst) + 1)
                    .scaleEffect(0.9 + burst * 0.9)
                    .frame(width: 200, height: 200)
                    .allowsHitTesting(false)
            }

            unlockButton
                .modifier(ShakeEffect(travel: 12, shakes: shakes))
        }
        .frame(width: 260, height: 260)
        // 陀螺仪: 整组轻微 3D 倾斜
        .rotation3DEffect(.degrees(motion.x * 10), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(-motion.y * 10), axis: (x: 1, y: 0, z: 0))
    }

    private var idleRing: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [buttonTint.opacity(0.0), buttonTint.opacity(0.9), .white.opacity(0.8), buttonTint.opacity(0.0)],
                        center: .center
                    ),
                    lineWidth: 2.5
                )
                .rotationEffect(.degrees((t * (busy ? 120 : 24)).truncatingRemainder(dividingBy: 360)))
        }
        .frame(width: 208, height: 208)
        .allowsHitTesting(false)
    }

    private var rippleLayer: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.9 + Double(i) / 3.0).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(buttonTint.opacity(1 - phase), lineWidth: 2.5)
                        .scaleEffect(0.85 + phase * 0.35)
                }
            }
        }
        .frame(width: 230, height: 230)
        .allowsHitTesting(false)
    }

    // ─── 中心开门大按钮 ───
    private var unlockButton: some View {
        Group {
            if #available(iOS 26.0, *) {
                if transparentFill {
                    Button { Task { await ble.unlock() } } label: { unlockButtonLabel }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .tint(buttonTint)
                        .disabled(busy || !s.isConfigured())
                } else {
                    Button { Task { await ble.unlock() } } label: { unlockButtonLabel }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(buttonTint)
                        .disabled(busy || !s.isConfigured())
                }
            } else {
                Button { Task { await ble.unlock() } } label: {
                    unlockButtonLabel
                        .background(
                            Circle().fill(transparentFill ? Color.clear : buttonTint)
                        )
                        .overlay(
                            Circle().stroke(buttonTint, lineWidth: transparentFill ? 3 : 0)
                        )
                }
                .buttonStyle(.plain)
                .disabled(busy || !s.isConfigured())
            }
        }
        .frame(width: 180, height: 180)
    }

    private var unlockButtonLabel: some View {
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
        .frame(width: 156, height: 156)
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
        .frame(maxWidth: .infinity)
    }

    private var statusCardContent: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(buttonTint)
                .frame(width: 10, height: 10)
            Text(ble.statusText)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
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
