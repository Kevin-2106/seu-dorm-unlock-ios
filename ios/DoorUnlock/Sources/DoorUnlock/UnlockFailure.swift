import Foundation

/// 一次开门失败的原因 + 用户能点的补救动作。
/// 首页状态卡片根据它显示中文原因和按钮，不用再对着错误码猜。
struct UnlockFailure: Equatable {
    enum Action: Equatable {
        case refreshCredentials   // 用已保存的账号重新拉取凭据
        case openLogin            // 还没登录过，去设置里登录
    }

    var title: String
    var hint: String = ""
    var code: Int? = nil
    var action: Action? = nil

    /// 没有错误码的失败 (蓝牙未开、没扫到锁、超时...)
    static func plain(_ title: String, hint: String = "", action: Action? = nil) -> UnlockFailure {
        UnlockFailure(title: title, hint: hint, code: nil, action: action)
    }

    /// 锁返回的 resultCode。含义来自上游文档和实测，没把握的地方措辞留有余地。
    static func fromCode(_ code: Int) -> UnlockFailure {
        switch code {
        case 14, 15:
            return UnlockFailure(
                title: "锁不认这份凭据 (\(code))",
                hint: "可能是你在锁上的授权被删除，或项目ID对不上。重新拉取凭据通常能解决。",
                code: code, action: .refreshCredentials)
        case 24:
            return UnlockFailure(
                title: "凭据已过期 (24)",
                hint: "重新拉取一份新凭据即可。",
                code: code, action: .refreshCredentials)
        case 25:
            return UnlockFailure(
                title: "离线开门次数用完 (25)",
                hint: "需要联网从服务器刷新凭据。",
                code: code, action: .refreshCredentials)
        case 27:
            return UnlockFailure(
                title: "锁要求更换密钥 (27)",
                hint: "再开一次门，App 会向锁索取新密钥。",
                code: code, action: nil)
        default:
            return UnlockFailure(
                title: "开门失败 (错误码 \(code))",
                hint: "先试试重新拉取凭据；仍然失败请到 设置 → 诊断 复制日志反馈。",
                code: code, action: .refreshCredentials)
        }
    }
}
