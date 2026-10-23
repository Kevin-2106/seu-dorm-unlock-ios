import AppIntents
import Foundation

extension Notification.Name {
    static let doorUnlockRequested = Notification.Name("doorUnlockRequested")
}

/// 外部 (快捷指令 / Action 按钮 / Siri) 请求开门的待处理标记。
/// 冷启动时 intent 的 perform 可能先于界面创建，通知会丢；界面出现后再读这个标记补上。
enum UnlockRequest {
    static var pending = false
}

/// 主 app 内的 App Intent —— 不需要任何扩展 (不占 App ID 名额)。
/// 免费 Apple ID 只有 10 个 App ID 额度，小组件扩展装不上时，用"快捷指令"里的这个动作
/// 一样能把"开门"放到锁屏 (快捷指令小组件/控制)、Action 按钮、轻点背面、Siri。
@available(iOS 16.0, *)
struct OpenDoorIntent: AppIntent {
    static var title: LocalizedStringResource = "开门"
    static var description = IntentDescription("打开 app 并立即扫描蓝牙开门")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UnlockRequest.pending = true
        NotificationCenter.default.post(name: .doorUnlockRequested, object: nil)
        return .result()
    }
}

@available(iOS 16.0, *)
struct DoorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDoorIntent(),
            phrases: ["用 \(.applicationName) 开门", "\(.applicationName) 开门"],
            shortTitle: "开门",
            systemImageName: "lock.fill"
        )
    }
}
