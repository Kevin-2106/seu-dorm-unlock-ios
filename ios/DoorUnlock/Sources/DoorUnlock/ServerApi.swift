import Foundation
import CryptoKit

/// 住理生活服务器 API (移植自 Android 版 ServerApi.kt)
///
/// MVP 范围: 登录 + 拉取地址/凭证信息。
/// 「在线重置离线计数器」(createCommand/parseCommand/onlineReset) 在 Android 源码里
/// 已被标注为「旧方案，已废弃」，这里不做移植；24/25 错误统一走 fetchAddress 刷新 chainKey。
enum ServerApi {

    private static let session = URLSession(configuration: {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 10
        return c
    }())

    /// 签名密钥 (从原 App 提取, 所有 API 请求共用)
    private static let SIGN_KEY = "6d5dbb85b949447a95ff8fda9a9b759b"

    private static let PLATFORM_SERVER = "https://pm.whxinna.com"

    /// 网络调试日志 (环形缓冲，供 UI 显示用于排查真实接口返回结构)
    static var debugLog: [String] = []
    private static func logD(_ s: String) {
        debugLog.append(s)
        if debugLog.count > 300 { debugLog.removeFirst() }
        print("[ServerApi] \(s)")
    }

    private static func apiServer() -> String {
        let s = SettingsManager.shared.projectServerUrl
        return s.isEmpty ? PLATFORM_SERVER : s
    }

    private static func generateTimestamp() -> String {
        String(Int(Date().timeIntervalSince1970))
    }

    private static func generateNonce() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<32).map { _ in chars.randomElement()! })
    }

    /// 等价于 Android 端 org.json.JSONObject.quote(value) 去掉首尾引号、再去空格后的效果：
    /// 对值做 JSON 字符串转义 (反斜杠/引号/控制字符)，再把残余的 `"` 和空格剥掉。
    private static func jsonEscapedStripped(_ value: String) -> String {
        var out = ""
        for ch in value.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "" // 转义后产生的 \" 里引号会被原逻辑剥掉，这里直接省略引号本身
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else if ch == " " {
                    continue // 原逻辑最后会把空格去掉
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out
    }

    /// 签名算法: MD5
    private static func sign(_ params: [String: String], key: String = SIGN_KEY) -> String {
        let sorted = params.sorted { $0.key < $1.key }
        let query = sorted
            .filter { !$0.value.isEmpty }
            .map { "\($0.key)=\(jsonEscapedStripped($0.value))" }
            .joined(separator: "&")
        let raw = "\(query)&key=\(key)"
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// 解码 JS encode: btoa(encodeURIComponent(str)).replace(/\+/g,"-").replace(/\//g,"_")
    private static func decodeBase64Data(_ data: String) -> String {
        var fixed = data.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while fixed.count % 4 != 0 { fixed += "=" }
        guard let decoded = Data(base64Encoded: fixed) else { return "" }
        return String(data: decoded, encoding: .utf8) ?? ""
    }

    /// org.json 的 optString 会自动把数字类型转成字符串；JSONSerialization 不会，
    /// 必须手动兜底 NSNumber —— 否则像 server_appid/server_id 这种服务器返回数字的字段，
    /// `as? String` 直接拿空，后续签名必填参数缺失，被服务器判定 api_sign_error。
    private static func anyToString(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    private static func parseServerInfo(_ info: [String: Any]) {
        let s = SettingsManager.shared
        let srv = anyToString(info["server_addr"]); if !srv.isEmpty { s.projectServerUrl = srv }
        let secret = anyToString(info["appsecret"]); if !secret.isEmpty { s.projectSignKey = secret }
        let sessionSecret = anyToString(info["session_secret"]); if !sessionSecret.isEmpty { s.projectSessionKey = sessionSecret }
        let serverAppId = anyToString(info["server_appid"]); if !serverAppId.isEmpty { s.serverAppId = serverAppId }
        let serverId = anyToString(info["server_id"]); if !serverId.isEmpty { s.serverId = serverId }
    }

    /// gt 客户端签名: 自动注入 user_id/pid/appid/identitycode
    private static func signGtRequest(_ pairs: [String: String] = [:]) -> [String: String] {
        let s = SettingsManager.shared
        let key = !s.projectSessionKey.isEmpty ? s.projectSessionKey
            : (!s.projectSignKey.isEmpty ? s.projectSignKey : SIGN_KEY)
        var params = pairs
        if !s.userId.isEmpty { params["user_id"] = s.userId }
        if !s.serverAppId.isEmpty { params["pid"] = s.serverAppId }
        if !s.serverId.isEmpty { params["appid"] = s.serverId }
        if !s.identityCode.isEmpty { params["identitycode"] = s.identityCode }
        params["timestamp"] = generateTimestamp()
        params["noncestr"] = generateNonce()
        params["sign"] = sign(params, key: key)
        return params
    }

    private static func signRequest(_ pairs: [String: String] = [:], key: String = SIGN_KEY) -> [String: String] {
        var params = pairs
        params["timestamp"] = generateTimestamp()
        params["noncestr"] = generateNonce()
        params["sign"] = sign(params, key: key)
        return params
    }

    private static func query(_ params: [String: String], encode: Bool = false) -> String {
        params.map { k, v in
            encode ? "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)" : "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private static func getJSON(_ urlString: String) async throws -> (Int, [String: Any], String) {
        guard let url = URL(string: urlString) else { throw ServerApiError.badURL }
        let (data, resp) = try await session.data(from: url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        let parsed = try? JSONSerialization.jsonObject(with: data)
        let json = (parsed as? [String: Any]) ?? [:]
        return (code, json, bodyStr)
    }

    enum ServerApiError: Error, LocalizedError {
        case badURL
        case notLoggedIn
        case noData(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "URL 构造失败"
            case .notLoggedIn: return "未登录"
            case .noData(let m): return m
            }
        }
    }

    // ─── 登录 ───

    struct LoginResult {
        var success = false
        var token = ""
        var error = ""
    }

    static func login(phone: String, password: String) async -> LoginResult {
        let signed = signRequest(["phone": phone, "pwd": password])
        let q = query(signed)

        // 试所有服务器 (与 Android 版一致)
        let servers = [
            "https://pm.whxinna.com",
            "https://m5-zhuli.whxinna.com",
            "https://p4-zhuli.whxinna.com",
            "https://f5-zhuli.whxinna.com"
        ]
        var attempts: [String] = []

        for srv in servers {
            do {
                let (code, json, bodyStr) = try await getJSON("\(srv)/webapi/users/login?\(q)")
                attempts.append("\(srv) → \(code) \(bodyStr.prefix(120))")
                logD("login \(srv) → HTTP \(code)")
                logD("login body(完整): \(bodyStr)")
                if code == 404 || bodyStr.isEmpty { continue }
                guard (json["result"] as? Bool) == true else {
                    logD("login result!=true, 顶层keys=\(json.keys.sorted())")
                    continue
                }

                var token = json["platform_token"] as? String ?? ""

                var dataJson = json["data"] as? [String: Any]
                if dataJson == nil, let dataB64 = json["data"] as? String, !dataB64.isEmpty {
                    let decoded = decodeBase64Data(dataB64)
                    logD("data(base64解码后): \(decoded)")
                    if let d = decoded.data(using: .utf8) {
                        dataJson = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                    }
                }
                logD("dataJson keys=\(dataJson?.keys.sorted() ?? [])")

                let s = SettingsManager.shared
                if let dj = dataJson {
                    if token.isEmpty { token = dj["platform_token"] as? String ?? "" }
                    if let userInfo = dj["user_info"] as? [String: Any] {
                        logD("user_info keys=\(userInfo.keys.sorted())")
                        let uid = anyToString(userInfo["id"])
                        let idCode = anyToString(userInfo["identity_code"])
                        if !uid.isEmpty { s.userId = uid }
                        if !idCode.isEmpty { s.identityCode = idCode }
                    } else {
                        logD("dataJson 无 user_info 字段")
                    }
                    if let info = dj["server_info"] as? [String: Any] {
                        logD("server_info keys=\(info.keys.sorted())")
                        parseServerInfo(info)
                    } else {
                        logD("dataJson 无 server_info 字段")
                    }
                }

                if let topInfo = json["server_info"] as? [String: Any] {
                    logD("顶层 server_info keys=\(topInfo.keys.sorted())")
                    parseServerInfo(topInfo)
                }
                if let topSrv = json["server_addr"] as? String, !topSrv.isEmpty { s.projectServerUrl = topSrv }

                logD("解析结果: userId=\(s.userId) identityCode前10=\(s.identityCode.prefix(10)) projectServerUrl=\(s.projectServerUrl) projectSignKey前8=\(s.projectSignKey.prefix(8)) projectSessionKey前8=\(s.projectSessionKey.prefix(8)) serverAppId=\(s.serverAppId) serverId=\(s.serverId)")

                if !token.isEmpty {
                    s.platformToken = token
                    return LoginResult(success: true, token: token)
                }
            } catch {
                attempts.append("\(srv) → 异常: \(error.localizedDescription)")
                continue
            }
        }
        return LoginResult(success: false, error: attempts.joined(separator: "\n"))
    }

    // ─── 地址 + 门锁信息 (原 App getAddress() 调用的 /webapi/v1/staff/credentials) ───

    struct AddressInfo {
        var buildingName = ""
        var floorName = ""
        var roomName = ""
        var deviceId: Int32 = 0
        var deviceName = ""
        var mac = ""
        var batteryLevel = 0
        var credentialId: Int32 = 0
        var chainKey = ""
    }

    static func fetchAddress() async throws -> AddressInfo {
        let s = SettingsManager.shared
        guard !s.platformToken.isEmpty else { throw ServerApiError.notLoggedIn }
        guard !s.projectServerUrl.isEmpty else { throw ServerApiError.noData("未绑定项目") }

        let signed = signGtRequest()
        let q = query(signed, encode: true)
        let url = "\(s.projectServerUrl)/webapi/v1/staff/credentials?\(q)"
        logD("fetchAddress 请求: \(url)")
        logD("fetchAddress 签名参数(未编码): \(signed)")
        let (code, json, bodyStr) = try await getJSON(url)
        logD("fetchAddress 响应: HTTP \(code) body=\(bodyStr)")

        guard (json["result"] as? Bool) == true else {
            let msg = (json["msg"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (json["err_msg"] as? String) ?? String(bodyStr.prefix(200))
            throw ServerApiError.noData(msg)
        }

        var item: [String: Any]?
        if let arr = json["data"] as? [[String: Any]] {
            item = arr.first
        }
        if item == nil { item = json["data"] as? [String: Any] }
        if item == nil, let b64 = json["data"] as? String, !b64.isEmpty {
            let decoded = decodeBase64Data(b64)
            if let d = decoded.data(using: .utf8) {
                if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    item = obj
                } else if let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                    item = arr.first
                }
            }
        }
        guard let it = item else {
            return AddressInfo() // 无门锁地址 → 返回空结构，上层显示「未找到门锁设备」
        }

        let doorLock = (it["door_lock"] as? [String: Any]) ?? it
        let acc = (it["accommodation"] as? [String: Any]) ?? it

        func str(_ dict: [String: Any], _ key: String) -> String {
            (dict[key] as? String) ?? (dict[key] as? NSNumber)?.stringValue ?? ""
        }
        func intVal(_ dict: [String: Any], _ key: String) -> Int32 {
            Int32((dict[key] as? NSNumber)?.intValue ?? Int(str(dict, key)) ?? 0)
        }

        return AddressInfo(
            buildingName: str(acc, "building_name"),
            floorName: str(acc, "floor_name"),
            roomName: str(acc, "room_name"),
            deviceId: intVal(doorLock, "device_id"),
            deviceName: str(doorLock, "ble_name"),
            mac: str(doorLock, "ble_mac"),
            batteryLevel: Int(intVal(doorLock, "battery_level")),
            credentialId: intVal(doorLock, "credential_id"),
            chainKey: str(doorLock, "credential")
        )
    }
}
