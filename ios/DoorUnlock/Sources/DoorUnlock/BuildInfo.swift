import Foundation

/// 构建信息: 版本号 / CI 构建号 (Actions run 编号) / commit 短哈希。
/// 用来在 app 里确认装上的到底是哪一版 (侧载经常"以为装了其实没装上")。
enum BuildInfo {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    static var version: String { info["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { info["CFBundleVersion"] as? String ?? "?" }
    static var commit: String {
        let c = info["BuildCommit"] as? String ?? ""
        return c == "dev" ? "" : c
    }

    /// 例: "v1.0 (build 42 · a1b2c3d)"
    static var summary: String {
        "v\(version) (build \(build)" + (commit.isEmpty ? "" : " · \(commit)") + ")"
    }

    /// 小组件扩展有没有被装进来: 直接看 app 包里 PlugIns 目录有没有 .appex。
    /// SideStore 在 App ID 配额不够时会让你"移除 app extension"，那样这里就是 false。
    static var widgetExtensionInstalled: Bool {
        guard let url = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        else { return false }
        return items.contains { $0.pathExtension == "appex" }
    }
}
