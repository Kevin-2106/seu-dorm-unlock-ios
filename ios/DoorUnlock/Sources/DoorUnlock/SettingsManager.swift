import Foundation
import Security
import Combine

/// 凭证参数持久化存储 (移植自 Android 版 SettingsManager.kt)
///
/// 密码使用 Keychain，其余用 UserDefaults —— 与 Android 版用途一致，只是存储后端不同。
///
/// 遵循 ObservableObject: 单例本身不是靠 SwiftUI 的 @State 驱动的，光改 UserDefaults
/// 不会让任何界面自动刷新。给会影响界面显示的字段的 setter 都加一句
/// `objectWillChange.send()`，页面那边用 `@ObservedObject var settings = SettingsManager.shared`
/// 持有它，改了就能立刻反映到所有正在显示的界面上 (不用等 sheet 关闭之类的间接触发)。
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let deviceId = "device_id"
        static let projectId = "project_id"
        static let credentialId = "credential_id"
        static let chainKey = "chain_key"
        static let deviceMac = "device_mac"
        static let cachedPeripheralID = "cached_peripheral_id"
        static let agreedDisclaimer = "agreed_disclaimer"
        static let showLogs = "show_logs"
        static let loginPhone = "login_phone"
        static let platformToken = "platform_token"
        static let projectServerUrl = "project_server_url"
        static let projectSignKey = "project_sign_key"
        static let projectSessionKey = "project_session_key"
        static let userId = "user_id"
        static let serverAppId = "server_appid"
        static let serverId = "server_id"
        static let identityCode = "identity_code"
    }

    private enum KeychainKey {
        static let loginPassword = "login_password"
    }

    var deviceId: Int32 {
        get { Int32(defaults.integer(forKey: Key.deviceId)) }
        set { objectWillChange.send(); defaults.set(Int(newValue), forKey: Key.deviceId) }
    }

    var projectId: Int32 {
        get { Int32(defaults.integer(forKey: Key.projectId)) }
        set { objectWillChange.send(); defaults.set(Int(newValue), forKey: Key.projectId) }
    }

    var credentialId: Int32 {
        get { Int32(defaults.integer(forKey: Key.credentialId)) }
        set { objectWillChange.send(); defaults.set(Int(newValue), forKey: Key.credentialId) }
    }

    var chainKey: String {
        get { defaults.string(forKey: Key.chainKey) ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.chainKey) }
    }

    var deviceMac: String {
        get { defaults.string(forKey: Key.deviceMac) ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.deviceMac) }
    }

    /// 上次成功连接的 CBPeripheral.identifier（iOS 给每台设备+每个蓝牙外设配对关系分配的
    /// UUID，不是真实 MAC，且每台 iOS 设备看到的值不同，所以不放进可跨设备分享的配置码）。
    /// 下次开门先用这个直连，跳过几秒的广播扫描；拿不到再退回扫描。
    var cachedPeripheralID: String {
        get { defaults.string(forKey: Key.cachedPeripheralID) ?? "" }
        set { defaults.set(newValue, forKey: Key.cachedPeripheralID) }
    }

    /// BLE 扫描名称
    var bleName: String { "XN-\(deviceId)" }

    /// chainKey 是否已填写 (32 字节 = 64 hex 字符)
    func isConfigured() -> Bool { !chainKey.isEmpty && chainKey.count == 64 }

    var agreedDisclaimer: Bool {
        get { defaults.bool(forKey: Key.agreedDisclaimer) }
        set { defaults.set(newValue, forKey: Key.agreedDisclaimer) }
    }

    var showLogs: Bool {
        get { defaults.bool(forKey: Key.showLogs) }
        set { defaults.set(newValue, forKey: Key.showLogs) }
    }

    var loginPhone: String {
        get { defaults.string(forKey: Key.loginPhone) ?? "" }
        set { defaults.set(newValue, forKey: Key.loginPhone) }
    }

    /// 密码走 Keychain，不进 UserDefaults 明文 plist
    var loginPassword: String {
        get { Keychain.read(KeychainKey.loginPassword) ?? "" }
        set { Keychain.save(KeychainKey.loginPassword, value: newValue) }
    }

    var platformToken: String {
        get { defaults.string(forKey: Key.platformToken) ?? "" }
        set { defaults.set(newValue, forKey: Key.platformToken) }
    }

    var projectServerUrl: String {
        get { defaults.string(forKey: Key.projectServerUrl) ?? "" }
        set { defaults.set(newValue, forKey: Key.projectServerUrl) }
    }

    var projectSignKey: String {
        get { defaults.string(forKey: Key.projectSignKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.projectSignKey) }
    }

    var projectSessionKey: String {
        get { defaults.string(forKey: Key.projectSessionKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.projectSessionKey) }
    }

    var userId: String {
        get { defaults.string(forKey: Key.userId) ?? "" }
        set { defaults.set(newValue, forKey: Key.userId) }
    }

    var serverAppId: String {
        get { defaults.string(forKey: Key.serverAppId) ?? "" }
        set { defaults.set(newValue, forKey: Key.serverAppId) }
    }

    var serverId: String {
        get { defaults.string(forKey: Key.serverId) ?? "" }
        set { defaults.set(newValue, forKey: Key.serverId) }
    }

    var identityCode: String {
        get { defaults.string(forKey: Key.identityCode) ?? "" }
        set { defaults.set(newValue, forKey: Key.identityCode) }
    }

    func isLoggedIn() -> Bool { !platformToken.isEmpty }
}

/// 极简 Keychain 包装 (仅用于密码这一个字段)
enum Keychain {
    static func save(_ key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
