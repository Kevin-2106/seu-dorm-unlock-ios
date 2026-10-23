import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                // LabeledContent 是 iOS 16+，主 app 还要兼容 iOS 15，用 HStack
                HStack {
                    Text("版本")
                    Spacer()
                    Text(BuildInfo.summary).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack {
                    Text("小组件扩展")
                    Spacer()
                    Text(BuildInfo.widgetExtensionInstalled ? "已安装" : "未安装").foregroundStyle(.secondary)
                }
            } footer: {
                if !BuildInfo.widgetExtensionInstalled {
                    Text("未安装 = 侧载时被移除了 (免费 Apple ID 只有 10 个 App ID 额度，扩展要多占 1 个)。\n没有扩展也能用: 在\"快捷指令\"里添加\"开门\"动作，放到锁屏快捷指令控制 / Action 按钮 / 轻点背面 / Siri。")
                }
            }
            Section("项目") {
                if let url = URL(string: "https://github.com/Kevin-2106/seu-dorm-unlock-ios") {
                    Link("GitHub 仓库", destination: url)
                }
                if let url = URL(string: "https://github.com/Haa1024/SEU-Door-Unlock") {
                    Link("上游 Android 版 (协议来源)", destination: url)
                }
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
