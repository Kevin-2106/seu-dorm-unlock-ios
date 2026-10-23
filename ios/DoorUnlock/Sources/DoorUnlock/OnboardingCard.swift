import SwiftUI

/// 配置好门锁后、用户点「完成」之前，首页底部显示的三步上手清单。
struct OnboardingCard: View {
    @AppStorage("onboarding_done") private var done = false
    @ObservedObject private var log = UnlockLog.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        if !done && settings.isConfigured() {
            VStack(alignment: .leading, spacing: 8) {
                step(true, "已登录并拉取凭据")
                step(log.hasSuccess, "点中间的按钮开一次门试试")
                step(false, "锁屏添加小组件: 长按锁屏 → 自定义 → 点时间下方的栏 → 添加「门钥」。有 Action 按钮的机型可在 设置 → 操作按钮 → 快捷指令 选「开门」")
                Button("完成，不再显示") { done = true }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func step(_ checked: Bool, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checked ? Color.green : Color.white.opacity(0.5))
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
