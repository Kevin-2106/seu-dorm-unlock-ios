import Foundation
import Combine

/// 开锁按钮样式
enum ButtonLook: Int, CaseIterable, Identifiable {
    case glassSolid = 0   // iOS 26: .glassProminent (低版本自动退回实色)
    case solid = 1        // 实色填充，不透明度可调
    case clear = 2        // 无填充，只有描边 (iOS 26 以下的"透明"兜底)
    case glassClear = 3   // iOS 26: .glass(.clear) 官方 Liquid Glass 透明变体 (低版本自动退回描边)

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .glassSolid: return "玻璃实心 (iOS 26)"
        case .glassClear: return "玻璃透明 (iOS 26)"
        case .solid: return "实色填充"
        case .clear: return "描边透明 (无填充)"
        }
    }
}

/// 所有"拿不准的"视觉/震动参数集中在这里，设置页的滑块直接绑定，
/// 改完立刻生效，不用重新构建。每个属性改动时写回 UserDefaults。
final class Tuning: ObservableObject {
    static let shared = Tuning()
    private let d = UserDefaults.standard

    private static func num(_ k: String, _ def: Double) -> Double {
        (UserDefaults.standard.object(forKey: k) as? Double) ?? def
    }
    private static func flag(_ k: String, _ def: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: k) as? Bool) ?? def
    }

    // ─── 按钮 / 圆环 ───
    @Published var buttonLook: Int { didSet { d.set(buttonLook, forKey: "tn_buttonLook") } }
    @Published var fillOpacity: Double { didSet { d.set(fillOpacity, forKey: "tn_fillOpacity") } }
    @Published var ringWidth: Double { didSet { d.set(ringWidth, forKey: "tn_ringWidth") } }
    @Published var ringIntensity: Double { didSet { d.set(ringIntensity, forKey: "tn_ringIntensity") } }
    @Published var ringInvert: Bool { didSet { d.set(ringInvert, forKey: "tn_ringInvert") } }
    /// 玻璃透明时叠在玻璃上的状态色强度 (Glass.tint)
    @Published var glassTint: Double { didSet { d.set(glassTint, forKey: "tn_glassTint") } }
    /// clear 玻璃下面的半透明黑色衬底 (Apple 文档建议: 用 clear 时垫一层暗色保证内容可读)
    @Published var clearBacking: Double { didSet { d.set(clearBacking, forKey: "tn_clearBacking") } }

    // ─── 陀螺仪 ───
    @Published var tilt: Double { didSet { d.set(tilt, forKey: "tn_tilt") } }

    // ─── 蓄力 (开门中) ───
    @Published var chargeSeconds: Double { didSet { d.set(chargeSeconds, forKey: "tn_chargeSeconds") } }
    @Published var dim: Double { didSet { d.set(dim, forKey: "tn_dim") } }
    @Published var bloom: Double { didSet { d.set(bloom, forKey: "tn_bloom") } }
    @Published var rgbSplit: Double { didSet { d.set(rgbSplit, forKey: "tn_rgbSplit") } }
    @Published var flash: Double { didSet { d.set(flash, forKey: "tn_flash") } }

    // ─── 涟漪 ───
    @Published var rippleCount: Double { didSet { d.set(rippleCount, forKey: "tn_rippleCount") } }
    @Published var rippleSpeed: Double { didSet { d.set(rippleSpeed, forKey: "tn_rippleSpeed") } }
    @Published var rippleDistance: Double { didSet { d.set(rippleDistance, forKey: "tn_rippleDistance") } }
    @Published var rippleOpacity: Double { didSet { d.set(rippleOpacity, forKey: "tn_rippleOpacity") } }

    // ─── 粒子 ───
    @Published var particleCount: Double { didSet { d.set(particleCount, forKey: "tn_particleCount") } }
    @Published var particleSize: Double { didSet { d.set(particleSize, forKey: "tn_particleSize") } }
    @Published var warpCount: Double { didSet { d.set(warpCount, forKey: "tn_warpCount") } }
    @Published var warpSpeed: Double { didSet { d.set(warpSpeed, forKey: "tn_warpSpeed") } }
    @Published var warpStreak: Double { didSet { d.set(warpStreak, forKey: "tn_warpStreak") } }

    // ─── 震动 ───
    @Published var hapticsOn: Bool { didSet { d.set(hapticsOn, forKey: "tn_hapticsOn") } }
    @Published var hSearchIntensity: Double { didSet { d.set(hSearchIntensity, forKey: "tn_hSearchIntensity") } }
    @Published var hSearchSharpness: Double { didSet { d.set(hSearchSharpness, forKey: "tn_hSearchSharpness") } }
    @Published var hSuccessIntensity: Double { didSet { d.set(hSuccessIntensity, forKey: "tn_hSuccessIntensity") } }
    @Published var hFailIntensity: Double { didSet { d.set(hFailIntensity, forKey: "tn_hFailIntensity") } }

    private init() {
        // 兼容旧版"透明填充"开关
        let legacyClear = UserDefaults.standard.bool(forKey: "button_fill_transparent")
        buttonLook = (UserDefaults.standard.object(forKey: "tn_buttonLook") as? Int) ?? (legacyClear ? ButtonLook.glassClear.rawValue : 0)
        fillOpacity = Self.num("tn_fillOpacity", 0.9)
        ringWidth = Self.num("tn_ringWidth", 2.5)
        ringIntensity = Self.num("tn_ringIntensity", 1.0)
        ringInvert = Self.flag("tn_ringInvert", false)
        glassTint = Self.num("tn_glassTint", 0.15)
        clearBacking = Self.num("tn_clearBacking", 0.18)
        tilt = Self.num("tn_tilt", 0.6)
        chargeSeconds = Self.num("tn_chargeSeconds", 2.5)
        dim = Self.num("tn_dim", 0.5)
        bloom = Self.num("tn_bloom", 1.0)
        rgbSplit = Self.num("tn_rgbSplit", 3.0)
        flash = Self.num("tn_flash", 0.35)
        rippleCount = Self.num("tn_rippleCount", 3)
        rippleSpeed = Self.num("tn_rippleSpeed", 0.6)
        rippleDistance = Self.num("tn_rippleDistance", 0.5)
        rippleOpacity = Self.num("tn_rippleOpacity", 0.8)
        particleCount = Self.num("tn_particleCount", 60)
        particleSize = Self.num("tn_particleSize", 1.0)
        warpCount = Self.num("tn_warpCount", 90)
        warpSpeed = Self.num("tn_warpSpeed", 1.0)
        warpStreak = Self.num("tn_warpStreak", 1.0)
        hapticsOn = Self.flag("tn_hapticsOn", true)
        hSearchIntensity = Self.num("tn_hSearchIntensity", 0.6)
        hSearchSharpness = Self.num("tn_hSearchSharpness", 0.3)
        hSuccessIntensity = Self.num("tn_hSuccessIntensity", 1.0)
        hFailIntensity = Self.num("tn_hFailIntensity", 1.0)
    }

    func reset() {
        buttonLook = 0; fillOpacity = 0.9; ringWidth = 2.5; ringIntensity = 1.0; ringInvert = false
        glassTint = 0.15; clearBacking = 0.18
        tilt = 0.6
        chargeSeconds = 2.5; dim = 0.5; bloom = 1.0; rgbSplit = 3.0; flash = 0.35
        rippleCount = 3; rippleSpeed = 0.6; rippleDistance = 0.5; rippleOpacity = 0.8
        particleCount = 60; particleSize = 1.0
        warpCount = 90; warpSpeed = 1.0; warpStreak = 1.0
        hapticsOn = true; hSearchIntensity = 0.6; hSearchSharpness = 0.3
        hSuccessIntensity = 1.0; hFailIntensity = 1.0
    }
}
