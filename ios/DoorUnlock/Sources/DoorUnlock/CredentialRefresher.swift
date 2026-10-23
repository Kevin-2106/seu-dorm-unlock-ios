import Foundation

/// 用已保存的账号重新向服务器拉取凭据 (chainKey / credentialId)。
/// 开门失败后的「重新拉取」按钮、设置页按钮、蓝牙 24/25 自动恢复都走这里。
///
/// 优先复用已有会话 (登录会把官方 App 顶下线，能不登就不登)；
/// 拉取失败说明会话可能过期，才用 Keychain 里的账号密码重新登录一次再试。
@MainActor
enum CredentialRefresher {
    enum Outcome: Equatable {
        case ok
        case needLogin          // 没有保存的账号密码
        case failed(String)
    }

    static func hasSavedAccount() -> Bool {
        let s = SettingsManager.shared
        return !s.loginPhone.isEmpty && !s.loginPassword.isEmpty
    }

    static func refresh(log: (String) -> Void = { _ in }) async -> Outcome {
        let s = SettingsManager.shared
        if !s.isLoggedIn() {
            guard hasSavedAccount() else { return .needLogin }
            if let err = await login(log: log) { return .failed(err) }
        }
        do {
            try await fetchAndSave(log: log)
            return .ok
        } catch {
            log("拉取失败 (\(error.localizedDescription))，会话可能过期，重新登录一次再试")
            guard hasSavedAccount() else { return .needLogin }
            if let err = await login(log: log) { return .failed(err) }
            do {
                try await fetchAndSave(log: log)
                return .ok
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    /// 返回 nil 表示成功，否则是错误描述
    private static func login(log: (String) -> Void) async -> String? {
        let s = SettingsManager.shared
        log("使用已保存的账号登录...")
        let result = await ServerApi.login(phone: s.loginPhone, password: s.loginPassword)
        if result.success { log("登录成功"); return nil }
        log("登录失败: \(result.error)")
        return "登录失败: \(result.error)"
    }

    private static func fetchAndSave(log: (String) -> Void) async throws {
        let addr = try await ServerApi.fetchAddress()
        guard !addr.chainKey.isEmpty else { throw RefreshError.empty }
        let s = SettingsManager.shared
        s.chainKey = addr.chainKey
        s.credentialId = addr.credentialId
        log("已从服务器获取新 chainKey: \(addr.chainKey.prefix(8))…")
    }

    private enum RefreshError: LocalizedError {
        case empty
        var errorDescription: String? { "服务器没有返回凭据" }
    }
}
