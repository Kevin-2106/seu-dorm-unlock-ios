import SwiftUI
import UIKit
import CoreMotion
import CoreHaptics

// MARK: - 缓动 / 噪声小工具

func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}

func easeOutCubic(_ x: Double) -> Double {
    1 - pow(1 - max(0, min(1, x)), 3)
}

func fract(_ x: Double) -> Double { x - floor(x) }

/// 确定性伪随机 (同一个 i/k 永远给同一个值)，用来给粒子分配固定的随机属性
func rnd(_ i: Int, _ k: Int) -> Double {
    fract(sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453)
}

// MARK: - 震动

/// CoreHaptics 引擎封装 (iPhone 8 及以上支持)。
/// iPhone 7 没有 CoreHaptics 硬件能力，`isSupported == false`，由 `Haptics` 回退到系统震动。
final class HapticEngine {
    static let shared = HapticEngine()
    private var engine: CHHapticEngine?
    private var searchPlayer: CHHapticAdvancedPatternPlayer?
    private init() {}

    var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    private func ensureEngine() -> CHHapticEngine? {
        guard isSupported else { return nil }
        if let e = engine { return e }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.stoppedHandler = { [weak self] _ in
                self?.engine = nil
                self?.searchPlayer = nil
            }
            e.resetHandler = { [weak self] in
                self?.engine = nil
                self?.searchPlayer = nil
            }
            try e.start()
            engine = e
            return e
        } catch {
            return nil
        }
    }

    private func clamp(_ v: Float) -> Float { min(1, max(0, v)) }

    private func transient(_ t: TimeInterval, _ i: Float, _ s: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(i)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp(s))
            ],
            relativeTime: t
        )
    }

    private func continuous(_ t: TimeInterval, _ dur: TimeInterval, _ i: Float, _ s: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(i)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp(s))
            ],
            relativeTime: t,
            duration: dur
        )
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard let e = ensureEngine() else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try e.makePlayer(with: pattern)
            try e.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    /// 搜索/开门中: 持续的细腻嗡鸣，强度在前几秒由弱渐强 (蓄力感)。
    func startSearch(_ k: Float, sharpness: Float) {
        stopSearch()
        guard let e = ensureEngine() else { return }
        let event = continuous(0, 30, 1.0, sharpness)
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: clamp(0.35 * k)),
                CHHapticParameterCurve.ControlPoint(relativeTime: 3, value: clamp(k)),
                CHHapticParameterCurve.ControlPoint(relativeTime: 30, value: clamp(k))
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [curve])
            let player = try e.makeAdvancedPlayer(with: pattern)
            try e.start()
            try player.start(atTime: CHHapticTimeImmediate)
            searchPlayer = player
        } catch {}
    }

    func stopSearch() {
        try? searchPlayer?.stop(atTime: CHHapticTimeImmediate)
        searchPlayer = nil
    }

    /// 成功: 类似支付成功的"嗒嗒"双击 + 一小段衰减尾音
    func success(_ k: Float) {
        let tail = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.32, value: 0)
            ],
            relativeTime: 0.11
        )
        play([
            transient(0, k, 0.85),
            transient(0.11, k, 0.85),
            continuous(0.11, 0.32, 0.6 * k, 0.25)
        ], curves: [tail])
    }

    /// 失败: 抖两下 —— 每下都是一记硬敲加一小段短促的嗡
    func failure(_ k: Float) {
        var events: [CHHapticEvent] = []
        for i in 0..<2 {
            let t = Double(i) * 0.26
            events.append(transient(t, k, 1.0))
            events.append(continuous(t, 0.16, 0.9 * k, 0.75))
        }
        play(events)
    }
}

/// 对外的震动入口：读 Tuning 里的开关和强度；不支持 CoreHaptics 的机型回退到系统震动。
enum Haptics {
    private static var t: Tuning { Tuning.shared }
    private static var core: HapticEngine { HapticEngine.shared }

    static func searchStart() {
        guard t.hapticsOn else { return }
        if core.isSupported {
            core.startSearch(Float(t.hSearchIntensity), sharpness: Float(t.hSearchSharpness))
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    static func searchStop() { core.stopSearch() }

    /// 仅在不支持 CoreHaptics 的机型上，搜索期间用它做"心跳"节拍
    static func tick() {
        guard t.hapticsOn, !core.isSupported else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }

    static func success() {
        guard t.hapticsOn else { return }
        if core.isSupported {
            core.success(Float(t.hSuccessIntensity))
        } else {
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        }
    }

    static func failure() {
        guard t.hapticsOn else { return }
        if core.isSupported {
            core.failure(Float(t.hFailIntensity))
        } else {
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.prepare()
            g.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { g.impactOccurred(intensity: 1.0) }
        }
    }
}

// MARK: - 陀螺仪

/// 陀螺仪倾斜量 (归一化到大约 -1...1)。用重力向量而不是姿态角：
/// 手拿在手里的"自然姿势"附近比较稳，不会在竖直握持时抖。
final class MotionManager: ObservableObject {
    @Published var x: Double = 0   // 左右倾斜 (相对"自然握持姿势"的偏移，给视差用)
    @Published var y: Double = 0   // 前后倾斜
    @Published var gx: Double = 0  // 重力在屏幕平面上的投影，向右为正 (给圆环亮端指向用)
    @Published var gy: Double = 0  // 向下为正；竖直握持 ≈ +1，平放 ≈ 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 24.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let g = motion?.gravity else { return }
            // 竖直握持时 gravity.y ≈ -1；平时手持略后仰，以 -0.7 附近为中性点
            let targetX = max(-1, min(1, g.x * 1.6))
            let targetY = max(-1, min(1, (g.y + 0.7) * 2.0))
            self.x = self.x * 0.85 + targetX * 0.15   // 低通滤波
            self.y = self.y * 0.85 + targetY * 0.15
            // 设备坐标 y 轴朝上，所以屏幕坐标下的"向下"= -gravity.y
            self.gx = self.gx * 0.8 + g.x * 0.2
            self.gy = self.gy * 0.8 + (-g.y) * 0.2
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

// MARK: - 动画辅助

/// 失败时按钮左右抖动。`shakes` 每增加 1 = 来回抖一个周期。
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 12
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 2), y: 0))
    }
}

/// 把两个 Double 状态变成"每一帧都会重新求值内容"的可动画容器。
/// 普通 @State 动画只会插值视图修饰符的数值，Canvas/自定义计算里读到的永远是终值；
/// 用 Animatable 视图包一层，SwiftUI 每帧把插值后的 a/b 传进来，内容才能随动画平滑变化。
struct AnimScope<Content: View>: View, Animatable {
    var a: Double
    var b: Double
    let content: (Double, Double) -> Content

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(a, b) }
        set {
            a = newValue.first
            b = newValue.second
        }
    }

    var body: some View { content(a, b) }
}

// MARK: - 粒子

/// 跃迁粒子的相位时钟。相位必须是"累积"出来的 (速度变化时位置才连续)，
/// 不能直接用 t * 速度 —— 速度一变，所有粒子会瞬间跳位。引用类型，由 HomeView 持有。
final class WarpClock {
    var phase: Double = 0
    var last: Double = 0
}

/// 两层粒子:
/// 1. 环境尘埃: 不同"深度"缓慢上飘，随陀螺仪视差；进入按钮区域会淡出
///    (否则按钮是透明样式时，能看到粒子在按钮后面)。
/// 2. 跃迁粒子 (蓄力时): 从圆环外缘"出生"，沿径向加速飞出屏幕、飞出后在圆环处重生 ——
///    新粒子出现、旧粒子出屏幕消失，不会出现在按钮背后，也没有"整块屏幕形粒子云旋转收缩"的问题。
///    蓄力越深速度越快、拖尾越长；成功时(pulse)拖尾爆发一下再收。
struct ParticleCanvas: View {
    let charge: Double
    let pulse: Double
    let center: CGPoint
    let tiltX: Double
    let tiltY: Double
    let count: Int
    let warpCount: Int
    let warpSpeed: Double
    let warpStreak: Double
    let sizeScale: Double
    let tint: Color
    let clock: WarpClock

    /// 按钮半径 (90) + 圆环外缘，尘埃在这个范围内淡出
    private let clearInner: Double = 96
    private let clearOuter: Double = 130
    /// 跃迁粒子出生半径 (略大于圆环半径 104)
    private let spawnRadius: CGFloat = 110

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate

                // 累积相位 (限制单帧最大步长，避免切后台回来时跳变)
                let dt = clock.last == 0 ? 0 : min(0.1, t - clock.last)
                clock.last = t
                let speedNow = warpSpeed * (2.2 * charge * charge + 3.5 * pulse)
                clock.phase += dt * (0.10 + speedNow)

                drawDust(&gc, size: size, t: t)
                drawWarp(&gc, size: size, speedNow: speedNow)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawDust(_ gc: inout GraphicsContext, size: CGSize, t: Double) {
        let dim = 1 - 0.65 * charge   // 蓄力时尘埃让位给跃迁粒子
        for i in 0..<max(0, count) {
            let r1 = rnd(i, 1), r2 = rnd(i, 2), r3 = rnd(i, 3), r4 = rnd(i, 4)
            let depth = 0.25 + 0.75 * r3

            // 缓慢上飘 + 轻微横向摆动 + 陀螺仪视差 (越近 depth 越大，位移越多)
            var x = CGFloat(fract(r1 + sin(t * 0.12 * (0.5 + r4) + r2 * 6.283) * 0.03)) * size.width
            var y = CGFloat(fract(r2 - t * 0.010 * (0.4 + depth))) * size.height
            x -= CGFloat(tiltX * 36 * depth)
            y -= CGFloat(tiltY * 36 * depth)

            var dx = x - center.x
            var dy = y - center.y
            if pulse > 0.001 {   // 成功: 向外一推
                let push = CGFloat(1 + pulse * 0.7 * depth)
                dx *= push
                dy *= push
            }
            let px = center.x + dx
            let py = center.y + dy

            // 按钮区域内淡出
            let dist = Double(hypot(px - center.x, py - center.y))
            let clear = smoothstep(clearInner, clearOuter, dist)
            if clear < 0.01 { continue }

            let twinkle = 0.6 + 0.4 * sin(t * (0.8 + r4) + r1 * 6.283)
            let o = min(0.95, (0.12 + 0.5 * depth) * twinkle * (1 + pulse * 1.2)) * dim * clear
            let s = CGFloat((1.2 + 2.2 * depth) * sizeScale)
            let halo = s * 3.4

            gc.fill(
                Path(ellipseIn: CGRect(x: px - halo / 2, y: py - halo / 2, width: halo, height: halo)),
                with: .color(tint.opacity(o * 0.16))
            )
            gc.fill(
                Path(ellipseIn: CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)),
                with: .color(Color.white.opacity(o))
            )
        }
    }

    private func drawWarp(_ gc: inout GraphicsContext, size: CGSize, speedNow: Double) {
        let visible = max(smoothstep(0.0, 0.18, charge), pulse)
        guard visible > 0.01, warpCount > 0 else { return }

        // 灭点随手机倾斜轻微偏移，增加透视感
        let vp = CGPoint(x: center.x - CGFloat(tiltX * 18), y: center.y - CGFloat(tiltY * 18))
        let maxR = max(
            hypot(vp.x, vp.y),
            hypot(size.width - vp.x, vp.y),
            hypot(vp.x, size.height - vp.y),
            hypot(size.width - vp.x, size.height - vp.y)
        ) * 1.05
        let span = maxR - spawnRadius

        // 拖尾长度占"寿命进度"的比例: 速度越快越长
        let streakU = min(0.3, 0.015 + 0.05 * speedNow * warpStreak)

        for j in 0..<warpCount {
            let a1 = rnd(j, 11), a2 = rnd(j, 12), a3 = rnd(j, 13)
            let theta = a1 * 2 * Double.pi
            let life = 0.7 + a2 * 0.9                 // 寿命不同 → 每颗速度不同，层次感
            let u = fract(clock.phase / life + a3)    // 0=刚在圆环出生, 1=飞出屏幕
            let u0 = max(0, u - streakU)

            // 半径随进度二次以上增长: 先慢后快，像迎面飞来 (非线性)
            let r1 = spawnRadius + span * CGFloat(pow(u, 2.2))
            let r0 = spawnRadius + span * CGFloat(pow(u0, 2.2))
            let dirX = CGFloat(cos(theta)), dirY = CGFloat(sin(theta))
            let p1 = CGPoint(x: vp.x + dirX * r1, y: vp.y + dirY * r1)
            let p0 = CGPoint(x: vp.x + dirX * r0, y: vp.y + dirY * r0)

            // 出生时透明渐显 (从圆环"长"出来)，临近出屏时淡出
            let o = smoothstep(0.0, 0.10, u) * (1 - smoothstep(0.82, 1.0, u)) * visible * (0.35 + 0.65 * a2)
            if o < 0.01 { continue }
            let w = CGFloat((0.8 + 2.6 * pow(u, 1.5)) * sizeScale)

            var path = Path()
            path.move(to: p0)
            path.addLine(to: p1)
            gc.stroke(path, with: .color(tint.opacity(o * 0.28)), style: StrokeStyle(lineWidth: w * 3, lineCap: .round))
            gc.stroke(path, with: .color(Color.white.opacity(o)), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
    }
}
