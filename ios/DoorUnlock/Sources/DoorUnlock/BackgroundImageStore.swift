import Foundation
import UIKit
import Combine

/// 首页自定义背景图片的存取。存文件系统而不是 UserDefaults —— 图片数据不适合塞进 plist。
/// 遵循 ObservableObject，选好图/清除后页面能立刻刷新，不用额外的通知机制。
final class BackgroundImageStore: ObservableObject {
    static let shared = BackgroundImageStore()

    @Published private(set) var image: UIImage?

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home_background.jpg")
    }

    private init() {
        image = UIImage(contentsOfFile: fileURL.path)
    }

    func save(_ newImage: UIImage) {
        guard let data = newImage.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: fileURL, options: .atomic)
        image = newImage
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        image = nil
    }
}
