import SwiftUI
import UIKit
import CoreMotion

/// 触感反馈：几种状态用明显不同的"手感"，不靠盯屏幕也能分辨结果。
enum Haptics {
    /// 开始搜索/连接：一下中等力度
    static func start() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        g.impactOccurred()
    }

    /// 搜索期间的轻微"心跳"节拍
    static func tick() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred(intensity: 0.45)
    }

    /// 成功：系统的"上扬双击"成功反馈，干脆利落
    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    /// 失败：三连 rigid 硬敲，跟成功的手感完全不同
    static func failure() {
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.prepare()
        g.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { g.impactOccurred(intensity: 1.0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { g.impactOccurred(intensity: 1.0) }
    }
}

/// 陀螺仪倾斜量 (归一化到大约 -1...1)，用来给首页做视差/高光的小把戏。
/// 用重力向量而不是姿态角：手机拿在手里的"自然姿势"附近比较稳，不会在竖直握持时抖。
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
            // 低通滤波，避免抖动
            self.x = self.x * 0.85 + targetX * 0.15
            self.y = self.y * 0.85 + targetY * 0.15
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

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
