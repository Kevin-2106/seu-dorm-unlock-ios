import SwiftUI

/// 视觉/震动参数调节页。所有滑块直接绑定 Tuning.shared，改完回首页立刻生效，不用重新构建。
struct TuningView: View {
    @ObservedObject private var tuning = Tuning.shared

    var body: some View {
        Form {
            Section("按钮与圆环") {
                Picker("按钮样式", selection: $tuning.buttonLook) {
                    ForEach(ButtonLook.allCases) { Text($0.title).tag($0.rawValue) }
                }
                SliderRow(title: "实色填充不透明度", value: $tuning.fillOpacity, range: 0...1)
                SliderRow(title: "玻璃透明: 状态色强度", value: $tuning.glassTint, range: 0...0.6)
                SliderRow(title: "透明样式: 暗色衬底", value: $tuning.clearBacking, range: 0...0.6)
                SliderRow(title: "圆环粗细", value: $tuning.ringWidth, range: 1...6)
                SliderRow(title: "圆环亮度", value: $tuning.ringIntensity, range: 0...1.5)
                Toggle("反转圆环渐变方向", isOn: $tuning.ringInvert)
            }

            Section {
                SliderRow(title: "倾斜/视差强度", value: $tuning.tilt, range: 0...2)
            } header: {
                Text("陀螺仪")
            } footer: {
                Text("0 = 完全关闭。手机放桌上不会动，拿起来才有效果。")
            }

            Section("开门中 (蓄力)") {
                SliderRow(title: "蓄力时长(秒)", value: $tuning.chargeSeconds, range: 0.8...6)
                SliderRow(title: "背景变暗程度", value: $tuning.dim, range: 0...0.9)
                SliderRow(title: "Bloom 泛光强度", value: $tuning.bloom, range: 0...2)
                SliderRow(title: "RGB 分离(pt)", value: $tuning.rgbSplit, range: 0...8)
                SliderRow(title: "成功/失败闪色强度", value: $tuning.flash, range: 0...0.8)
            }

            Section("涟漪 (从圆环出发)") {
                SliderRow(title: "数量", value: $tuning.rippleCount, range: 1...6, format: "%.0f")
                SliderRow(title: "速度(圈/秒)", value: $tuning.rippleSpeed, range: 0.2...2)
                SliderRow(title: "扩散距离", value: $tuning.rippleDistance, range: 0.1...1.2)
                SliderRow(title: "最大不透明度", value: $tuning.rippleOpacity, range: 0...1)
            }

            Section("粒子") {
                SliderRow(title: "数量 (0 = 关闭)", value: $tuning.particleCount, range: 0...150, format: "%.0f")
                SliderRow(title: "大小", value: $tuning.particleSize, range: 0.4...2.5)
            }

            Section {
                Toggle("启用震动", isOn: $tuning.hapticsOn)
                SliderRow(title: "搜索嗡鸣强度", value: $tuning.hSearchIntensity, range: 0...1)
                SliderRow(title: "搜索嗡鸣锐度 (低=柔和细腻)", value: $tuning.hSearchSharpness, range: 0...1)
                SliderRow(title: "成功震动强度", value: $tuning.hSuccessIntensity, range: 0...1)
                SliderRow(title: "失败震动强度", value: $tuning.hFailIntensity, range: 0...1)
                Button("试震: 搜索嗡鸣 (2 秒)") {
                    Haptics.searchStart()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Haptics.searchStop() }
                }
                Button("试震: 成功") { Haptics.success() }
                Button("试震: 失败") { Haptics.failure() }
            } header: {
                Text("震动")
            } footer: {
                Text("iPhone 8 及以上用 CoreHaptics (可调强度/锐度)；iPhone 7 不支持，自动回退到系统震动，滑块对它无效。")
            }

            Section {
                Button("恢复全部默认值", role: .destructive) { tuning.reset() }
            }
        }
        .navigationTitle("视觉与震动调节")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
