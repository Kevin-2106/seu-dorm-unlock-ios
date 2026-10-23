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
        static let autoNFC = "auto_nfc"
        static let primaryMethod = "primary_method"
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
        static let chainKey = "chain_key"
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

    /// chainKey 是开门的实际凭据，优先存 Keychain。
    ///
    /// 迁移/回退策略 (宁可多存一份也不能把钥匙弄丢):
    /// - 读: Keychain 有就用；没有就读旧的 UserDefaults，并尝试迁到 Keychain。
    /// - 写: 先写 Keychain 并读回校验，通过了才删 UserDefaults 里的副本；
    ///   写失败 (有些侧载签名下没有 Keychain 权限) 就留在 UserDefaults 里，不丢。
    var chainKey: String {
        get {
            if let cached = chainKeyCache { return cached }
            let value = loadChainKey()
            chainKeyCache = value
            return value
        }
        set {
            objectWillChange.send()
            chainKeyCache = newValue
            storeChainKey(newValue)
        }
    }

    private var chainKeyCache: String?

    /// 当前 chainKey 实际存在哪，给「关于」页显示
    var chainKeyStorage: String {
        if Keychain.read(KeychainKey.chainKey) != nil { return "Keychain" }
        if defaults.string(forKey: Key.chainKey) != nil { return "本地 (Keychain 不可用，已回退)" }
        return "无"
    }

    private func loadChainKey() -> String {
        if let k = Keychain.read(KeychainKey.chainKey), !k.isEmpty { return k }
        let legacy = defaults.string(forKey: Key.chainKey) ?? ""
        if !legacy.isEmpty { storeChainKey(legacy) }   // 一次性迁移
        return legacy
    }

    private func storeChainKey(_ value: String) {
        if value.isEmpty {
            Keychain.delete(KeychainKey.chainKey)
            defaults.removeObject(forKey: Key.chainKey)
            return
        }
        if Keychain.save(KeychainKey.chainKey, value: value), Keychain.read(KeychainKey.chainKey) == value {
            defaults.removeObject(forKey: Key.chainKey)
        } else {
            defaults.set(value, forKey: Key.chainKey)
        }
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

    /// 打开 App / 回到前台时自动进入 NFC 持续监听 (默认开)。只用蓝牙的人可以关掉，免得每次弹系统 NFC 面板。
    var autoNFC: Bool {
        get { defaults.object(forKey: Key.autoNFC) as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.autoNFC) }
    }

    /// 首页大按钮、锁屏小组件/控制、快捷指令「开门」用哪种方式 (默认蓝牙)。
    /// 另一种方式在首页底部作为小按钮备选。
    var primaryMethod: UnlockMethod {
        get { UnlockMethod(rawValue: defaults.string(forKey: Key.primaryMethod) ?? "") ?? .ble }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: Key.primaryMethod) }
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

/// 极简 Keychain 包装 (密码、chainKey)
enum Keychain {
    @discardableResult
    static func save(_ key: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
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

enum UnlockMethod: String, CaseIterable, Identifiable {
    case ble, nfc
    var id: String { rawValue }
    var title: String { self == .ble ? "蓝牙" : "NFC" }
}
