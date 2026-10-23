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
    @Published var x: Double = 0   // 左右倾斜
    @Published var y: Double = 0   // 前后倾斜

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

/// 空间感粒子: 不同"深度"的尘埃缓慢上飘，深度越大越亮越大，随陀螺仪做视差；
/// 蓄力时向按钮中心汇聚并旋转，成功时向外炸开。
struct ParticleCanvas: View {
    let charge: Double
    let pulse: Double
    let center: CGPoint
    let tiltX: Double
    let tiltY: Double
    let count: Int
    let sizeScale: Double
    let tint: Color

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<max(0, count) {
                    let r1 = rnd(i, 1), r2 = rnd(i, 2), r3 = rnd(i, 3), r4 = rnd(i, 4)
                    let depth = 0.25 + 0.75 * r3

                    // 基础位置: 缓慢上飘 + 轻微横向摆动
                    var x = CGFloat(fract(r1 + sin(t * 0.12 * (0.5 + r4) + r2 * 6.283) * 0.03)) * size.width
                    var y = CGFloat(fract(r2 - t * 0.010 * (0.4 + depth))) * size.height
                    // 陀螺仪视差: 越近(depth 大)移动越多
                    x -= CGFloat(tiltX * 36 * depth)
                    y -= CGFloat(tiltY * 36 * depth)

                    var dx = x - center.x
                    var dy = y - center.y

                    // 蓄力: 向按钮中心汇聚并旋转
                    if charge > 0.001 {
                        let pull = CGFloat(charge * charge * 0.85)
                        let ang = charge * (0.7 + 0.8 * depth)
                        let ca = CGFloat(cos(ang)), sa = CGFloat(sin(ang))
                        let rx = dx * ca - dy * sa
                        let ry = dx * sa + dy * ca
                        dx = rx * (1 - pull)
                        dy = ry * (1 - pull)
                    }
                    // 成功: 向外炸开
                    if pulse > 0.001 {
                        let push = CGFloat(1 + pulse * 0.7 * depth)
                        dx *= push
                        dy *= push
                    }

                    let px = center.x + dx
                    let py = center.y + dy
                    let twinkle = 0.6 + 0.4 * sin(t * (0.8 + r4) + r1 * 6.283)
                    let o = min(0.95, (0.12 + 0.5 * depth) * twinkle * (1 + charge * 0.9 + pulse * 1.2))
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
        }
        .allowsHitTesting(false)
    }
}
