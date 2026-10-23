import SwiftUI
import UIKit

/// 用来把"开门按钮簇"的中心点传给背景层的粒子画布 (汇聚/炸开都围绕它)。
private struct ClusterCenterKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

/// 首页：只留"开门"这一件事，参数配置/日志都挪到设置页。
///
/// 布局要点 (之前踩过的坑):
/// - 背景必须用 .background { } 挂，不能当 ZStack 兄弟节点: scaledToFill 的图片尺寸
///   比屏幕大，作为兄弟节点会撑大父布局，导致状态卡片被拉到图片宽度、溢出屏幕。
/// - 不套 NavigationView: 首页不需要导航栏，套了会在顶部多出一条不透明的栏。
/// - 倾斜不用 rotation3DEffect: 它默认透视系数很强，左右倾斜时一侧"靠近镜头"
///   整体会变大。改成分层视差 (不同层按"深度"位移不同)，不改变尺寸。
struct HomeView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager
    @ObservedObject private var s = SettingsManager.shared
    @ObservedObject private var background = BackgroundImageStore.shared
    @ObservedObject private var tuning = Tuning.shared
    @StateObject private var motion = MotionManager()

    @State private var showSettings = false
    @State private var breathe = false        // 待机呼吸光晕
    @State private var charge: Double = 0     // 蓄力 0...1 (开门中缓慢上升)
    @State private var pulse: Double = 0      // 成功时粒子向外一推再回落
    @State private var burst: Double = 0      // 成功时圆环向外炸开
    @State private var shakes: CGFloat = 0    // 失败时按钮抖动
    @State private var dimLevel: Double = 0   // 开门中背景变暗
    @State private var flashAlpha: Double = 0 // 成功/失败闪色
    @State private var flashColor: Color = .green

    /// 仅在不支持 CoreHaptics 的机型 (iPhone 7) 上用来做"心跳"节拍
    private let ticker = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    private var busy: Bool {
        ble.state == .scanning || ble.state == .connecting || ble.state == .unlocking
    }

    private var look: ButtonLook { ButtonLook(rawValue: tuning.buttonLook) ?? .glassSolid }

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
        // 粒子在内容后面、背景图前面: 先挂粒子，再挂背景
        .backgroundPreferenceValue(ClusterCenterKey.self) { anchor in
            particleLayer(anchor: anchor)
        }
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
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onDisappear {
            motion.stop()
            Haptics.searchStop()
        }
        .onReceive(ticker) { _ in
            if busy { Haptics.tick() }
        }
        .onChange(of: busy) { isBusy in
            if isBusy {
                Haptics.searchStart()
                // 蓄力曲线: 慢起步、越来越快 (非线性)
                withAnimation(.timingCurve(0.55, 0.0, 0.85, 0.35, duration: tuning.chargeSeconds)) {
                    charge = 1
                }
                withAnimation(.easeInOut(duration: 0.9)) { dimLevel = tuning.dim }
            } else {
                Haptics.searchStop()
                withAnimation(.easeOut(duration: 0.5)) { charge = 0 }
                withAnimation(.easeInOut(duration: 0.7)) { dimLevel = 0 }
            }
        }
        .onChange(of: ble.state) { newState in
            switch newState {
            case .success:
                Haptics.searchStop()
                Haptics.success()
                playBurst()
                flash(.green, times: 1)
            case .failed:
                Haptics.searchStop()
                Haptics.failure()
                withAnimation(.linear(duration: 0.5)) { shakes += 2 }
                flash(.red, times: 2)
            default:
                break
            }
        }
        .onChange(of: nfc.statusText) { text in
            if text.hasPrefix("开门成功") || text.hasPrefix("门已打开") {
                Haptics.success()
                playBurst()
                flash(.green, times: 1)
            } else if text.hasPrefix("开门失败") || text.hasPrefix("门锁无响应") {
                Haptics.failure()
                withAnimation(.linear(duration: 0.5)) { shakes += 2 }
                flash(.red, times: 2)
            }
        }
    }

    // MARK: - 一次性效果

    private func playBurst() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            burst = 0
            pulse = 0
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.9)) { burst = 1 }
            withAnimation(.easeOut(duration: 0.3)) { pulse = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 1.2)) { pulse = 0 }
        }
    }

    /// 全屏轻微闪色然后恢复: 成功闪绿一下，失败闪红两下
    private func flash(_ color: Color, times: Int) {
        flashColor = color
        for i in 0..<times {
            let delay = Double(i) * 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.1)) { flashAlpha = tuning.flash }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1) {
                withAnimation(.easeIn(duration: 0.45)) { flashAlpha = 0 }
            }
        }
    }

    // MARK: - 背景

    /// 自定义图片(暗角遮罩+陀螺仪视差) 或 默认深色渐变；开门中变暗、成功/失败闪色。
    private var backgroundLayer: some View {
        ZStack {
            if let img = background.image {
                // Color.clear 占满提议尺寸，图片只作为 overlay 并被 clipped，
                // 这样图片自身(更大)的尺寸不会反过来影响布局。
                Color.clear
                    .overlay(
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(1.12)
                            .offset(x: CGFloat(-motion.x * 14 * tuning.tilt), y: CGFloat(-motion.y * 14 * tuning.tilt))
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
            Color.black.opacity(dimLevel)
            flashColor.opacity(flashAlpha)
        }
    }

    private func particleLayer(anchor: Anchor<CGPoint>?) -> some View {
        GeometryReader { proxy in
            let center = anchor.map { proxy[$0] } ?? CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.45)
            AnimScope(a: charge, b: pulse) { c, p in
                ParticleCanvas(
                    charge: max(0, min(1, c)),
                    pulse: max(0, min(1, p)),
                    center: center,
                    tiltX: motion.x * tuning.tilt,
                    tiltY: motion.y * tuning.tilt,
                    count: Int(tuning.particleCount),
                    sizeScale: tuning.particleSize,
                    tint: buttonTint
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - 设置按钮 (固定位置，不是 toolbar)

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

    // MARK: - 设备摘要

    private var deviceSummary: some View {
        VStack(spacing: 4) {
            // 用 String 拼接而不是直接插值 Int32，避免被格式化成 "2,284,408"
            Text(s.deviceId == 0 ? "未配置门锁" : "XN-" + String(s.deviceId))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            if !s.isConfigured() {
                Text("请先去设置页登录拉取凭证").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 开门按钮簇

    /// 按钮 + 周围所有特效。AnimScope 让 charge 每帧插值后重新求值内容，
    /// 里面再套 TimelineView 驱动圆环/涟漪的连续动画。
    private var unlockCluster: some View {
        AnimScope(a: charge, b: pulse) { cRaw, _ in
            clusterTimeline(c: max(0, min(1, cRaw)))
        }
        .frame(width: 300, height: 300)
        .anchorPreference(key: ClusterCenterKey.self, value: .center) { $0 }
    }

    private func clusterTimeline(c: Double) -> some View {
        TimelineView(.animation) { ctx in
            clusterBody(t: ctx.date.timeIntervalSinceReferenceDate, c: c)
        }
    }

    private func clusterBody(t: Double, c: Double) -> some View {
        let k = tuning.tilt
        // 视差: 光晕在"远处"(反向小幅漂移)，圆环/按钮在"近处"(同向)，层与层之间有相对位移
        let farOffset = CGSize(width: -motion.x * 12 * k, height: -motion.y * 12 * k)
        let ringOffset = CGSize(width: motion.x * 5 * k, height: motion.y * 5 * k)
        let buttonOffset = CGSize(width: motion.x * 9 * k, height: motion.y * 9 * k)
        return ZStack {
            glow(c: c).offset(farOffset)
            if busy { rippleLayer(t: t) }
            ringLayer(t: t, c: c).offset(ringOffset)
            if burst > 0 { burstRing }
            unlockButton(c: c, t: t)
                .offset(buttonOffset)
        }
    }

    private func glow(c: Double) -> some View {
        ZStack {
            Circle()
                .fill(buttonTint.opacity(0.35 + 0.25 * c))
                .frame(width: (breathe ? 230 : 195) - 40 * c, height: (breathe ? 230 : 195) - 40 * c)
                .blur(radius: 26)
                .opacity(busy ? 0.95 : 0.55)
            // 蓄力 bloom: 越蓄越亮的一团泛光
            Circle()
                .fill(buttonTint.opacity(min(1, c * tuning.bloom * 0.55)))
                .frame(width: 240, height: 240)
                .blur(radius: 42)
                .blendMode(.plusLighter)
        }
    }

    // MARK: 圆环

    private func rgb(of color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// 圆环渐变的"彗星"角度跟随陀螺仪倾斜方向，叠一点缓慢摆动保持待机的生命感
    private func ringAngle(t: Double) -> Double {
        var a = atan2(motion.y, motion.x) * 180 / .pi
        if tuning.ringInvert { a += 180 }
        return a + 26 * sin(t * 0.6)
    }

    /// channel: nil=正常色; 0/1/2 = 只保留 R/G/B 通道 (用于 RGB 分离，三个通道叠加还原原色)
    private func ringStroke(channel: Int?, angle: Double) -> some View {
        let (tr, tg, tb) = rgb(of: buttonTint)
        func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
            switch channel {
            case 0?: return Color(red: r, green: 0, blue: 0).opacity(a)
            case 1?: return Color(red: 0, green: g, blue: 0).opacity(a)
            case 2?: return Color(red: 0, green: 0, blue: b).opacity(a)
            default: return Color(red: r, green: g, blue: b).opacity(a)
            }
        }
        let k = tuning.ringIntensity
        let w = CGFloat(tuning.ringWidth)
        return ZStack {
            Circle().strokeBorder(col(tr, tg, tb, 0.22 * k), lineWidth: w * 0.6)
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: col(tr, tg, tb, 0.0), location: 0.0),
                            .init(color: col(tr, tg, tb, 0.9 * k), location: 0.50),
                            .init(color: col(1, 1, 1, 0.9 * k), location: 0.68),
                            .init(color: col(tr, tg, tb, 0.0), location: 0.70),
                            .init(color: col(tr, tg, tb, 0.0), location: 1.0)
                        ]),
                        center: .center
                    ),
                    lineWidth: w
                )
                .rotationEffect(.degrees(angle))
        }
    }

    private func ringLayer(t: Double, c: Double) -> some View {
        let d = tuning.rgbSplit * pow(c, 1.4)
        let angle = ringAngle(t: t)
        let jitter = sin(t * 38) * 0.3 * d
        return ZStack {
            if d > 0.15 {
                ringStroke(channel: 0, angle: angle).offset(x: CGFloat(-(d + jitter))).blendMode(.plusLighter)
                ringStroke(channel: 1, angle: angle).blendMode(.plusLighter)
                ringStroke(channel: 2, angle: angle).offset(x: CGFloat(d + jitter)).blendMode(.plusLighter)
            } else {
                ringStroke(channel: nil, angle: angle)
            }
            // bloom: 模糊的同款圆环叠加
            ringStroke(channel: nil, angle: angle)
                .blur(radius: 7)
                .opacity(min(1, tuning.bloom * (0.3 + 0.7 * c)))
                .blendMode(.plusLighter)
        }
        .compositingGroup()
        .frame(width: 208, height: 208)
        .allowsHitTesting(false)
    }

    // MARK: 涟漪 (从圆环出发)

    /// 每道波: 从圆环的位置出发，一开始完全透明 → 离开圆环一小段后渐显 → 再渐隐消失；
    /// 半径用 ease-out (先快后慢)，透明度用 smoothstep，全程非线性。
    private func rippleLayer(t: Double) -> some View {
        let n = max(0, Int(tuning.rippleCount.rounded()))
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                ripple(index: i, of: n, t: t)
            }
        }
        .frame(width: 208, height: 208)
        .allowsHitTesting(false)
    }

    private func ripple(index i: Int, of n: Int, t: Double) -> some View {
        let p = fract(t * tuning.rippleSpeed + Double(i) / Double(max(n, 1)))
        let grow = easeOutCubic(p)
        let alpha = smoothstep(0.04, 0.22, p) * (1 - smoothstep(0.30, 1.0, p))
        return Circle()
            .stroke(buttonTint.opacity(alpha * tuning.rippleOpacity), lineWidth: CGFloat(2.4 * (1 - 0.6 * p)))
            .scaleEffect(1 + tuning.rippleDistance * grow)
    }

    private var burstRing: some View {
        Circle()
            .stroke(Color.green.opacity(1 - burst), lineWidth: CGFloat(6 * (1 - burst) + 1))
            .scaleEffect(0.9 + burst * 0.9)
            .frame(width: 208, height: 208)
            .allowsHitTesting(false)
    }

    // MARK: 按钮本体

    private func unlockButton(c: Double, t: Double) -> some View {
        buttonByLook(c: c, t: t)
            .frame(width: 180, height: 180)
            .scaleEffect(1 - 0.045 * c)   // 蓄力: 微微收缩
            .modifier(ShakeEffect(travel: 12, shakes: shakes))
    }

    @ViewBuilder
    private func buttonByLook(c: Double, t: Double) -> some View {
        switch look {
        case .glassSolid:
            if #available(iOS 26.0, *) {
                glassSolidButton(c: c, t: t)
            } else {
                customButton(look: .solid, c: c, t: t)
            }
        case .glassClear:
            if #available(iOS 26.0, *) {
                glassClearButton(c: c, t: t)
            } else {
                customButton(look: .clear, c: c, t: t)
            }
        case .solid, .clear:
            customButton(look: look, c: c, t: t)
        }
    }

    private var unlockDisabled: Bool { busy || !s.isConfigured() }

    @available(iOS 26.0, *)
    private func glassSolidButton(c: Double, t: Double) -> some View {
        Button { Task { await ble.unlock() } } label: { labelView(c: c, t: t) }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(buttonTint)
            .disabled(unlockDisabled)
    }

    /// Apple 文档: PrimitiveButtonStyle.glass(_:) (iOS 26.0) + Glass.clear 变体；
    /// 文档提示 clear 玻璃下面要垫一层半透明暗色保证内容可读 —— clearBacking 可调。
    @available(iOS 26.0, *)
    private func glassClearButton(c: Double, t: Double) -> some View {
        Button { Task { await ble.unlock() } } label: { labelView(c: c, t: t) }
            .buttonStyle(.glass(.clear.tint(buttonTint.opacity(tuning.glassTint)).interactive()))
            .buttonBorderShape(.circle)
            .disabled(unlockDisabled)
            .background(Circle().fill(Color.black.opacity(tuning.clearBacking)).frame(width: 176, height: 176))
    }

    private func customButton(look: ButtonLook, c: Double, t: Double) -> some View {
        Button { Task { await ble.unlock() } } label: {
            labelView(c: c, t: t)
                .background(buttonFill(look: look))
                .overlay(Circle().stroke(Color.white.opacity(look == .clear ? 0.3 : 0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(unlockDisabled)
    }

    private func buttonFill(look: ButtonLook) -> some View {
        ZStack {
            if look == .clear {
                Circle().fill(Color.black.opacity(tuning.clearBacking))
            } else {
                Circle().fill(buttonTint.opacity(tuning.fillOpacity))
                // 高光随陀螺仪移动 (被裁在圆内)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: 60))
                        .frame(width: 120, height: 120)
                        .offset(x: CGFloat(motion.x * 34 * tuning.tilt), y: CGFloat(motion.y * 34 * tuning.tilt) - 14)
                }
                .frame(width: 156, height: 156)
                .clipShape(Circle())
            }
        }
    }

    // MARK: 按钮文字/图标: bloom + RGB 分离

    private var labelContent: some View {
        VStack(spacing: 10) {
            Image(systemName: ble.state == .success ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 44, weight: .semibold))
            Text(busy ? "开门中" : "开门")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: 156, height: 156)
    }

    private func labelView(c: Double, t: Double) -> some View {
        let d = tuning.rgbSplit * pow(c, 1.4)
        let jitter = sin(t * 38) * 0.3 * d
        return ZStack {
            if d > 0.15 {
                labelContent.colorMultiply(Color(red: 1, green: 0, blue: 0)).offset(x: CGFloat(-(d + jitter))).blendMode(.plusLighter)
                labelContent.colorMultiply(Color(red: 0, green: 1, blue: 0)).blendMode(.plusLighter)
                labelContent.colorMultiply(Color(red: 0, green: 0, blue: 1)).offset(x: CGFloat(d + jitter)).blendMode(.plusLighter)
            } else {
                labelContent
            }
            // bloom
            labelContent
                .blur(radius: 8)
                .opacity(min(1, tuning.bloom * (0.12 + 0.88 * c)))
                .blendMode(.plusLighter)
        }
        .compositingGroup()
    }

    private var buttonTint: Color {
        switch ble.state {
        case .success: return .green
        case .failed: return .red
        default: return .blue
        }
    }

    // MARK: - 状态卡片

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

    // MARK: - NFC 持续监听提示条

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
