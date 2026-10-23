import Foundation
import UIKit

/// 门锁凭据的"配置码"——不是账号密码，是已经从服务器拉到的开门凭据
/// (deviceId/projectId/credentialId/chainKey)，可以在同一账号绑定的多台设备间
/// 直接复制粘贴导入，不用每台设备都重新输入手机号密码登录一次。
///
/// 之所以要专门做这个: 每次登录都会把官方 app 的会话顶下线 (单点登录)，
/// 多设备各自登录一次 = 反复踢对方下线，体验很差。拉过一次凭据之后，
/// 后面新设备直接导入配置码就行，不用再触发登录。
///
/// 注意: 不包含手机号/密码/platformToken 这些账号态的敏感信息，
/// 也不包含 cachedPeripheralID (那是每台 iOS 设备自己的蓝牙配对 UUID，不通用)。
struct ShareableConfig: Codable {
    let deviceId: Int32
    let projectId: Int32
    let credentialId: Int32
    let chainKey: String

    private static let prefix = "DOORCFG1:"

    static func fromCurrentSettings() -> ShareableConfig {
        let s = SettingsManager.shared
        return ShareableConfig(
            deviceId: s.deviceId,
            projectId: s.projectId,
            credentialId: s.credentialId,
            chainKey: s.chainKey
        )
    }

    /// 编码成一段可复制的文本 (JSON → base64url，带固定前缀方便识别/校验)
    func encoded() -> String {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.prefix + b64
    }

    enum DecodeError: Error, LocalizedError {
        case badFormat
        var errorDescription: String? {
            switch self {
            case .badFormat: return "不是有效的门锁配置码"
            }
        }
    }

    static func decode(_ text: String) throws -> ShareableConfig {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { throw DecodeError.badFormat }
        var b64 = String(trimmed.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let config = try? JSONDecoder().decode(ShareableConfig.self, from: data),
              config.deviceId != 0, config.chainKey.count == 64
        else { throw DecodeError.badFormat }
        return config
    }

    /// 应用到本机设置 (覆盖 deviceId/projectId/credentialId/chainKey)
    func apply() {
        let s = SettingsManager.shared
        s.deviceId = deviceId
        s.projectId = projectId
        s.credentialId = credentialId
        s.chainKey = chainKey
        // 新设备/新门锁的配置码，旧的蓝牙直连缓存不再适用
        s.cachedPeripheralID = ""
    }

    // ─── 剪贴板便捷方法 ───

    func copyToPasteboard() {
        UIPasteboard.general.string = encoded()
    }

    static func fromPasteboard() -> ShareableConfig? {
        guard let text = UIPasteboard.general.string else { return nil }
        return try? decode(text)
    }
}
