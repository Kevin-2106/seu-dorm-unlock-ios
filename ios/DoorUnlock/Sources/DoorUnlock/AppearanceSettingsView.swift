import SwiftUI
import PhotosUI

/// 外观与反馈: 首页背景、视觉与震动调节入口。
struct AppearanceSettingsView: View {
    @ObservedObject private var background = BackgroundImageStore.shared

    var body: some View {
        Form {
            Section("首页背景") {
                if #available(iOS 16.0, *) {
                    BackgroundPickerRow()
                } else {
                    Text("自定义背景需要 iOS 16 及以上").font(.caption).foregroundStyle(.secondary)
                }
                if background.image != nil {
                    Button("恢复默认背景", role: .destructive) { background.clear() }
                }
            }
            Section {
                NavigationLink("视觉与震动调节") { TuningView() }
            } footer: {
                Text("按钮样式、圆环、开门动效、粒子、震动强度等，改完回首页立刻生效。")
            }
        }
        .navigationTitle("外观与反馈")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// PhotosPickerItem 这个类型本身标了 @available(iOS 16, *)，哪怕只是当一个
/// @State 属性的类型声明，也会在 iOS15 部署目标下报 "only available in iOS 16"。
/// 拆成单独一个同样打了 @available 的子 View，只在 `if #available(iOS 16, *)` 分支里构造它。
@available(iOS 16.0, *)
private struct BackgroundPickerRow: View {
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            Label("选择背景图片", systemImage: "photo")
        }
        .onChange(of: pickedItem) { newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { return }
                BackgroundImageStore.shared.save(uiImage)
            }
        }
    }
}
