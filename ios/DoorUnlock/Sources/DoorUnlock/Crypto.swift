import Foundation

/// 住理生活 BLE/NFC 开门 - 加密算法 (移植自 Android 版 Crypto.kt，逐函数对应)
enum DoorCrypto {

    // ─── 常量 ───
    static let FIXED_KEY: [UInt8] = [
        0xAC, 0xAB, 0xBC, 0xDA,
        0xAE, 0xBF, 0x14, 0x26,
        0x35, 0x42, 0x54, 0x65,
        0x72, 0x87, 0x92, 0x01
    ]

    static let SERVICE_UUID = "0000FF12-0000-1000-8000-00805F9B34FB"
    static let WRITE_UUID = "0000FF01-0000-1000-8000-00805F9B34FB"
    static let READ_UUID = "0000FF02-0000-1000-8000-00805F9B34FB"

    static let CMD_CERT_HEAD = 0x74
    static let CMD_CERT_PACK = 0x75
    static let CMD_RECHAIN_REQ = 0x76
    static let CMD_PACK_READ = 0x77
    static let CMD_UNLOCK = 0x78

    static let RESP_CERT_HEAD = 116
    static let RESP_CERT_PACK = 117
    static let RESP_RECHAIN_KEY = 118
    static let RESP_PACK_READ = 119
    static let RESP_CHAIN_KEY = 120

    static let ERR_SUCCESS = 0
    static let ERR_NEED_UPDATE_KEY = 27
    static let ERR_DOOR_ALREADY_OPEN = 23
    static let ERR_EXPIRED_BUT_OPEN = 24

    static let CRC8_TABLE: [UInt8] = [
        0,94,188,226,97,63,221,131,194,156,126,32,163,253,31,65,
        157,195,33,127,252,162,64,30,95,1,227,189,62,96,130,220,
        35,125,159,193,66,28,254,160,225,191,93,3,128,222,60,98,
        190,224,2,92,223,129,99,61,124,34,192,158,29,67,161,255,
        70,24,250,164,39,121,155,197,132,218,56,102,229,187,89,7,
        219,133,103,57,186,228,6,88,25,71,165,251,120,38,196,154,
        101,59,217,135,4,90,184,230,167,249,27,69,198,152,122,36,
        248,166,68,26,153,199,37,123,58,100,134,216,91,5,231,185,
        140,210,48,110,237,179,81,15,78,16,242,172,47,113,147,205,
        17,79,173,243,112,46,204,146,211,141,111,49,178,236,14,80,
        175,241,19,77,206,144,114,44,109,51,209,143,12,82,176,238,
        50,108,142,208,83,13,239,177,240,174,76,18,145,207,45,115,
        202,148,118,40,171,245,23,73,8,86,180,234,105,55,213,139,
        87,9,235,181,54,104,138,212,149,203,41,119,244,170,72,22,
        233,183,85,11,136,214,52,106,43,117,151,201,74,20,246,168,
        116,42,200,150,21,75,169,247,182,232,10,84,215,137,107,53
    ]

    // ─── CRC8 ───
    static func crc8(_ data: [UInt8]) -> UInt8 {
        var result: UInt8 = 0
        for b in data {
            result = CRC8_TABLE[Int(result ^ b)]
        }
        return result
    }

    // ─── 设备密钥派生 (与 Kotlin/JS 源码逐步对应) ───
    // 等价说明: Kotlin 里 "把 deviceId 的 LE 字节按 BE 读" 就是对 deviceId 做一次整体字节序反转。
    static func deriveDeviceKey(_ deviceId: Int32) -> [UInt8] {
        let a: UInt32 = UInt32(bitPattern: deviceId).byteSwapped

        var n = [UInt32](repeating: 0, count: 4)
        for i in 0..<4 {
            // FIXED_KEY 按 4 字节一组，小端解码为 uint32 (与 ByteBuffer.order(LITTLE_ENDIAN).getInt() 等价)
            n[i] = UInt32(FIXED_KEY[4 * i])
                | (UInt32(FIXED_KEY[4 * i + 1]) << 8)
                | (UInt32(FIXED_KEY[4 * i + 2]) << 16)
                | (UInt32(FIXED_KEY[4 * i + 3]) << 24)
        }

        for i in 0..<4 {
            let ii = UInt32(i)
            // e = (2654435769 + 305419896*i) mod 2^32
            let e = UInt32((UInt64(2654435769) + UInt64(305419896) * UInt64(i)) & 0xFFFFFFFF)
            let t1 = a & e
            let t2 = a | e
            let t3 = (~a) ^ e
            // t = t1 + i + t2 - 2*i - t3  (全部按 32 位取模，等价于逐步 wrapping 运算)
            let t = t1 &+ ii &+ t2 &- (ii &+ ii) &- t3
            n[i] ^= t
        }

        var out = [UInt8]()
        out.reserveCapacity(16)
        for v in n {
            // 按大端写出 (与 ByteBuffer.order(BIG_ENDIAN).putInt() 等价)
            out.append(UInt8((v >> 24) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF))
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8(v & 0xFF))
        }
        return out
    }

    // ─── RC4 ───
    static func rc4(_ data: [UInt8], key: [UInt8]) -> [UInt8] {
        var s = [UInt8](0...255)
        var j = 0
        for i in 0..<256 {
            j = (j + Int(s[i]) + Int(key[i % key.count])) % 256
            s.swapAt(i, j)
        }

        var result = [UInt8](repeating: 0, count: data.count)
        var i = 0
        j = 0
        for k in 0..<data.count {
            i = (i + 1) % 256
            j = (j + Int(s[i])) % 256
            s.swapAt(i, j)
            let ks = s[(Int(s[i]) + Int(s[j])) % 256]
            result[k] = data[k] ^ ks
        }
        return result
    }

    // ─── 十六进制工具 ───
    static func hexToBytes(_ hex: String) -> [UInt8] {
        let h = hex.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "0x", with: "")
        var bytes = [UInt8]()
        var idx = h.startIndex
        while idx < h.endIndex {
            let next = h.index(idx, offsetBy: 2)
            bytes.append(UInt8(h[idx..<next], radix: 16) ?? 0)
            idx = next
        }
        return bytes
    }

    static func bytesToHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    static func intToLe4(_ value: Int32) -> [UInt8] {
        let v = UInt32(bitPattern: value)
        return [
            UInt8(v & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 24) & 0xFF)
        ]
    }

    // ─── 数据包构造 ───
    /// [0x14(1B)] [0x00(1B)] [cmd(1B)] [加密数据(16B)] [CRC8(1B)]
    /// 注意: CRC8 对原始(未加密)数据计算
    static func buildPacket(cmd: Int, encryptedData: [UInt8], originalForCrc: [UInt8]) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = 20
        packet[1] = 0
        packet[2] = UInt8(cmd)
        for i in 0..<min(16, encryptedData.count) {
            packet[3 + i] = encryptedData[i]
        }
        packet[19] = crc8(originalForCrc)
        return packet
    }

    // ─── 开门协议数据包 ───

    /// Step 1: 凭证头 (0x74)
    static func buildCredentialHead(chainKeyHex: String, deviceId: Int32, projectId: Int32) -> [UInt8] {
        let chainKey = hexToBytes(chainKeyHex)
        let projectIdBytes = intToLe4(projectId)
        let derivedKey = deriveDeviceKey(deviceId)

        let totalLen = chainKey.count + 4 + projectIdBytes.count // 32+4+4=40
        let packCount = Int(ceil(Double(totalLen) / 15.0))
        let allData = projectIdBytes + chainKey
        let dataCrc = crc8(allData)

        var header = [UInt8](repeating: 0, count: 16)
        header[0] = UInt8(totalLen & 0xFF)
        header[1] = UInt8((totalLen >> 8) & 0xFF)
        header[2] = UInt8(packCount)
        header[3] = dataCrc

        let encrypted = rc4(header, key: derivedKey)
        return buildPacket(cmd: CMD_CERT_HEAD, encryptedData: encrypted, originalForCrc: header)
    }

    /// Step 2: 凭证分包 (0x75)
    static func buildCredentialPacks(chainKeyHex: String, ran: Int32, deviceId: Int32, projectId: Int32) -> [[UInt8]] {
        let chainKey = hexToBytes(chainKeyHex)
        let projectIdBytes = intToLe4(projectId)
        let ranBytes = intToLe4(ran)

        let payload = ranBytes + projectIdBytes + chainKey // 40 字节
        let derivedKey = deriveDeviceKey(deviceId)

        var packs = [[UInt8]]()
        let chunkSize = 15
        var i = 0
        while i < payload.count {
            let end = min(i + chunkSize, payload.count)
            let chunk = Array(payload[i..<end])
            let packIndex = i / chunkSize

            var rawData = [UInt8]()
            rawData.append(UInt8(packIndex))
            rawData.append(contentsOf: chunk)

            var packData = [UInt8](repeating: 0, count: 16)
            for (idx, b) in rawData.enumerated() where idx < 16 { packData[idx] = b }

            let encrypted = rc4(packData, key: derivedKey)
            packs.append(buildPacket(cmd: CMD_CERT_PACK, encryptedData: encrypted, originalForCrc: packData))
            i = end
        }
        return packs
    }

    /// Step 3: 开锁命令 (0x78)
    static func buildUnlockCommand(deviceId: Int32) -> [UInt8] {
        let data = [UInt8](repeating: 0, count: 16)
        let derivedKey = deriveDeviceKey(deviceId)
        let encrypted = rc4(data, key: derivedKey)
        return buildPacket(cmd: CMD_UNLOCK, encryptedData: encrypted, originalForCrc: data)
    }

    /// 请求重链密钥 (0x76)
    static func buildRechainKeyRequest(credentialId: Int32, deviceId: Int32) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 16)
        let credBytes = intToLe4(credentialId)
        for i in 0..<4 { data[i] = credBytes[i] }
        let derivedKey = deriveDeviceKey(deviceId)
        let encrypted = rc4(data, key: derivedKey)
        return buildPacket(cmd: CMD_RECHAIN_REQ, encryptedData: encrypted, originalForCrc: data)
    }

    /// 读取密钥分包 (0x77)
    static func buildPackReadRequest(packIndex: Int, deviceId: Int32) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 16)
        data[0] = UInt8(packIndex)
        let derivedKey = deriveDeviceKey(deviceId)
        let encrypted = rc4(data, key: derivedKey)
        return buildPacket(cmd: CMD_PACK_READ, encryptedData: encrypted, originalForCrc: data)
    }

    // ─── 响应解析 ───

    struct ParseResult {
        var success = false
        var cmd = 0
        var resultCode = -1
        var isSuccess = false
        var ran: Int32 = 0
        var packCount = 0
        var totalLength = 0
        var crc8Val = 0
        var packIndex = 0
        var resultData = ""
        var seq: Int? = nil
        var doorAlreadyOpen = false
        var needUpdateKey = false
        var error: String? = nil
    }

    static func parseResponse(hexData: String, deviceId: Int32) -> ParseResult {
        let raw = hexToBytes(hexData)
        if raw.count < 20 {
            var r = ParseResult(); r.error = "数据长度错误: \(raw.count)"; return r
        }

        let cmd = Int(raw[2])
        let payload = Array(raw[3..<19])
        let expectedCrc = raw[19]

        let derivedKey = deriveDeviceKey(deviceId)
        let decrypted = rc4(payload, key: derivedKey)
        let actualCrc = crc8(decrypted)
        if actualCrc != expectedCrc {
            var r = ParseResult(); r.error = "CRC校验失败: 期望\(actualCrc), 实际\(expectedCrc)"; return r
        }

        switch cmd {
        case RESP_CERT_HEAD:
            let resultCode = Int(decrypted[0])
            var ran: Int32 = 0
            if decrypted.count >= 8 {
                ran = Int32(bitPattern: UInt32(decrypted[4]) | (UInt32(decrypted[5]) << 8)
                    | (UInt32(decrypted[6]) << 16) | (UInt32(decrypted[7]) << 24))
            }
            var r = ParseResult(); r.success = true; r.cmd = cmd; r.resultCode = resultCode
            r.isSuccess = resultCode == ERR_SUCCESS; r.ran = ran
            return r

        case RESP_CERT_PACK:
            var r = ParseResult(); r.success = true; r.cmd = cmd; r.resultCode = 0; r.isSuccess = true
            return r

        case RESP_RECHAIN_KEY:
            let resultCode = Int(decrypted[0])
            let packCount = Int(decrypted[1])
            let totalLen = Int(decrypted[2]) | (Int(decrypted[3]) << 8)
            let crcV = Int(decrypted[4])
            let doorOpen = resultCode == ERR_DOOR_ALREADY_OPEN
            var r = ParseResult(); r.success = true; r.cmd = cmd; r.resultCode = resultCode
            r.isSuccess = resultCode == ERR_SUCCESS || doorOpen
            r.packCount = packCount; r.totalLength = totalLen; r.crc8Val = crcV; r.doorAlreadyOpen = doorOpen
            return r

        case RESP_PACK_READ:
            let packIndex = Int(decrypted[0])
            let resultData = bytesToHex(Array(decrypted[1..<16]))
            var r = ParseResult(); r.success = true; r.cmd = cmd; r.resultCode = 0; r.isSuccess = true
            r.packIndex = packIndex; r.resultData = resultData
            return r

        case RESP_CHAIN_KEY:
            let resultCode = Int(decrypted[0])
            let seq: Int? = decrypted.count >= 5 ? Int(decrypted[4]) : nil
            let doorOpen = resultCode == ERR_DOOR_ALREADY_OPEN
            var r = ParseResult(); r.success = true; r.cmd = cmd; r.resultCode = resultCode
            r.isSuccess = resultCode == ERR_SUCCESS || doorOpen
            r.seq = seq; r.doorAlreadyOpen = doorOpen
            r.needUpdateKey = resultCode == ERR_NEED_UPDATE_KEY
            return r

        default:
            var r = ParseResult(); r.success = true; r.cmd = cmd; r.resultCode = Int(decrypted[0])
            r.isSuccess = false
            r.error = "未知命令: 0x\(String(cmd, radix: 16).uppercased())"
            return r
        }
    }

    struct PackData { let packIndex: Int; let resultData: String }

    /// 拼装多包 chainKey
    static func assembleChainKey(_ packs: [PackData], expectedLength: Int, expectedCrc: UInt8) throws -> [UInt8] {
        let sorted = packs.sorted { $0.packIndex < $1.packIndex }
        let allHex = sorted.map { $0.resultData }.joined()
        let raw = hexToBytes(allHex)
        let trimmed = Array(raw.prefix(expectedLength))
        guard trimmed.count == expectedLength else {
            throw NSError(domain: "DoorCrypto", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "chainKey长度不匹配: 期望\(expectedLength), 实际\(trimmed.count)"])
        }
        guard crc8(trimmed) == expectedCrc else {
            throw NSError(domain: "DoorCrypto", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "chainKey CRC校验失败"])
        }
        return trimmed
    }

    // ═══ NFC 门锁协议 (0xB1) ═══

    static let NFC_CMD_HEADER = 0xB1
    static let NFC_SUB_OPEN = 0x0D
    static let NFC_RESP_CMD_CRC_ERROR = 0xF0
    static let NFC_RESP_CMD_UNKNOWN = 0xF1

    static let NFC_ERROR_MESSAGES: [Int: String] = [
        0: "成功", 1: "设备已被占用", 2: "数据CRC校验错误", 3: "生成随机密钥失败",
        4: "用户凭证保存失败", 5: "开锁交换密钥失败", 6: "解密随机密钥失败",
        7: "未找到用户信息", 8: "钥匙类型不匹配", 9: "管理员随机数不匹配",
        10: "门锁状态已打开", 11: "已过有效期", 12: "离线次数已用完",
        13: "用户凭证更新失败", 14: "用户已删除", 15: "项目ID不一致",
        255: "未知错误"
    ]

    struct NfcParseResult {
        var success = false
        var resultCode = -1
        var message = ""
        var doorAlreadyOpen = false
        var newChainKeyHex: String? = nil
        var seq: Int? = nil
        var error: String? = nil
    }

    /// 构造 NFC 0xB1 开锁指令
    /// 帧格式: [0xB1][0x0D][密文长度][RC4密文][CRC8]
    static func buildNfcOpenCommand(deviceId: Int32, projectId: Int32, chainKeyHex: String) -> [UInt8] {
        let chain = hexToBytes(chainKeyHex)
        let plain = intToLe4(projectId) + chain
        let cipher = rc4(plain, key: deriveDeviceKey(deviceId))

        var packet = [UInt8](repeating: 0, count: 3 + cipher.count + 1)
        packet[0] = UInt8(NFC_CMD_HEADER)
        packet[1] = UInt8(NFC_SUB_OPEN)
        packet[2] = UInt8(cipher.count)
        for (i, b) in cipher.enumerated() { packet[3 + i] = b }

        let crcInput = [packet[1], packet[2]] + plain
        packet[packet.count - 1] = crc8(crcInput)
        return packet
    }

    /// 解析 NFC 0xB1 响应
    static func parseNfcResponse(_ raw: [UInt8], deviceId: Int32) -> NfcParseResult {
        if raw.isEmpty {
            var r = NfcParseResult(); r.error = "响应为空"; return r
        }

        var frame: [UInt8]? = nil
        if raw.count >= 4 {
            for start in 0...(raw.count - 4) {
                if Int(raw[start]) == NFC_CMD_HEADER {
                    frame = Array(raw[start...]); break
                }
            }
        }
        guard let f = frame else {
            var r = NfcParseResult()
            r.error = "响应不是NFC命令帧 (头\(min(8, raw.count))字节: \(bytesToHex(Array(raw.prefix(8)))))"
            return r
        }

        let subCmd = Int(f[1])
        if subCmd == NFC_RESP_CMD_CRC_ERROR {
            var r = NfcParseResult(); r.error = "锁回报: 数据CRC错误"; return r
        }
        if subCmd == NFC_RESP_CMD_UNKNOWN {
            var r = NfcParseResult(); r.error = "锁回报: 未知命令"; return r
        }

        let cipherLen = Int(f[2])
        guard f.count >= 3 + cipherLen + 1 else {
            var r = NfcParseResult(); r.error = "响应长度不足: \(f.count) < \(3 + cipherLen + 1)"; return r
        }

        let cipher = Array(f[3..<(3 + cipherLen)])
        let expectedCrc = f[3 + cipherLen]
        let decrypted = rc4(cipher, key: deriveDeviceKey(deviceId))
        let actualCrc = crc8([f[1], f[2]] + decrypted)
        guard actualCrc == expectedCrc else {
            var r = NfcParseResult(); r.error = "CRC校验失败: 期望\(expectedCrc) 实际\(actualCrc)"; return r
        }

        let resultCode = Int(decrypted[0])
        let doorAlreadyOpen = resultCode == 10
        let message = NFC_ERROR_MESSAGES[resultCode] ?? "未知结果码\(resultCode)"

        var newKey: String? = nil
        var seq: Int? = nil
        if resultCode == 0 || doorAlreadyOpen {
            if decrypted.count >= 36 {
                newKey = bytesToHex(Array(decrypted[4..<36]))
            }
            if decrypted.count >= 40 {
                seq = Int(decrypted[36]) | (Int(decrypted[37]) << 8)
                    | (Int(decrypted[38]) << 16) | (Int(decrypted[39]) << 24)
            }
        }

        var r = NfcParseResult()
        r.success = resultCode == 0 || doorAlreadyOpen
        r.resultCode = resultCode
        r.message = message
        r.doorAlreadyOpen = doorAlreadyOpen
        r.newChainKeyHex = newKey
        r.seq = seq
        return r
    }
}
