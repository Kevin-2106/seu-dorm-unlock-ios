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

    private static func parseServerInfo(_ info: [String: Any]) {
        let s = SettingsManager.shared
        if let v = info["server_addr"] as? String, !v.isEmpty { s.projectServerUrl = v }
        if let v = info["appsecret"] as? String, !v.isEmpty { s.projectSignKey = v }
        if let v = info["session_secret"] as? String, !v.isEmpty { s.projectSessionKey = v }
        if let v = info["server_appid"] as? String, !v.isEmpty { s.serverAppId = v }
        if let v = info["server_id"] as? String, !v.isEmpty { s.serverId = v }
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
                if code == 404 || bodyStr.isEmpty { continue }
                guard (json["result"] as? Bool) == true else { continue }

                var token = json["platform_token"] as? String ?? ""

                var dataJson = json["data"] as? [String: Any]
                if dataJson == nil, let dataB64 = json["data"] as? String, !dataB64.isEmpty {
                    let decoded = decodeBase64Data(dataB64)
                    if let d = decoded.data(using: .utf8) {
                        dataJson = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                    }
                }

                let s = SettingsManager.shared
                if let dj = dataJson {
                    if token.isEmpty { token = dj["platform_token"] as? String ?? "" }
                    if let userInfo = dj["user_info"] as? [String: Any] {
                        let uid = userInfo["id"] as? String ?? (userInfo["id"] as? NSNumber)?.stringValue ?? ""
                        let idCode = userInfo["identity_code"] as? String ?? ""
                        if !uid.isEmpty { s.userId = uid }
                        if !idCode.isEmpty { s.identityCode = idCode }
                    }
                    if let info = dj["server_info"] as? [String: Any] { parseServerInfo(info) }
                }

                if let topInfo = json["server_info"] as? [String: Any] { parseServerInfo(topInfo) }
                if let topSrv = json["server_addr"] as? String, !topSrv.isEmpty { s.projectServerUrl = topSrv }

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
        let (_, json, bodyStr) = try await getJSON("\(s.projectServerUrl)/webapi/v1/staff/credentials?\(q)")

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
