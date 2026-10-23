import WidgetKit
import SwiftUI
import AppIntents

/// 点按小组件/控制后唤起主 app，并由 app 的 onOpenURL 自动开始扫描蓝牙开门。
private let unlockURL = URL(string: "doorunlock://unlock")!

// MARK: - 锁屏/主屏小组件 (纯静态，不读 app 数据，不用 App Group)

struct DoorEntry: TimelineEntry {
    let date: Date
}

struct DoorProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoorEntry { DoorEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (DoorEntry) -> Void) {
        completion(DoorEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoorEntry>) -> Void) {
        completion(Timeline(entries: [DoorEntry(date: Date())], policy: .never))
    }
}

extension View {
    /// iOS 17+ 小组件必须用 containerBackground，否则内容会被系统当成"没适配"处理；
    /// 扩展最低是 iOS 16，所以分支处理。
    @ViewBuilder
    func doorWidgetBackground<B: View>(_ background: B) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { background }
        } else {
            self.background(background)
        }
    }
}

struct DoorWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(unlockURL)
            .doorWidgetBackground(backgroundView)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("开门").font(.headline)
                    Text("点按开始扫描蓝牙").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("点按开门", systemImage: "lock.fill")
        default:
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                Text("开门")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
        }
    }

    /// 锁屏的 accessory 系列由系统统一着色，背景必须透明；主屏小号用渐变。
    @ViewBuilder
    private var backgroundView: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.30, blue: 0.80), Color(red: 0.05, green: 0.07, blue: 0.20)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

struct DoorWidget: Widget {
    let kind = "DoorUnlockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoorProvider()) { _ in
            DoorWidgetView()
        }
        .configurationDisplayName("开门")
        .description("点按打开 app 并立即扫描蓝牙开门。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

// MARK: - 锁屏控制 (iOS 18+，可替换锁屏左下/右下角的手电筒/相机按钮)

@available(iOS 18.0, *)
struct DoorControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "DoorUnlockControl") {
            ControlWidgetButton(action: OpenURLIntent(unlockURL)) {
                Label("开门", systemImage: "lock.fill")
            }
        }
        .displayName("开门")
        .description("打开 app 并立即扫描蓝牙开门。")
    }
}

// MARK: - 入口

@main
struct DoorWidgetBundle: WidgetBundle {
    var body: some Widget {
        DoorWidget()
        if #available(iOS 18.0, *) {
            DoorControl()
        }
    }
}
