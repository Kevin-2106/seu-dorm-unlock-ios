import Foundation
import CoreNFC

/// NFC 开门管理器 (移植自 Android 版 NfcDoorLockManager.kt 的 0xB1 协议部分)
///
/// Android 实测结论: 门锁感应区是 ISO14443-A Type 2 标签 (ATQA=4400/SAK=0)，
/// 无 IsoDep，不走 ISO7816 封装，官方协议是对 NfcA 发裸帧。iOS 对应能力是
/// `NFCISO14443Tag.sendMiFareCommand` / `NFCMiFareTag.sendMiFareCommand` ——
/// 两者语义等价 (ISO14443-3 层裸帧收发)，具体落在哪个 case 取决于系统对标签
/// 芯片 (常见是 NTAG21x 系列) 的分类，所以两种 tag case 都处理。
@MainActor
final class DoorNFCManager: NSObject, ObservableObject {

    @Published var statusText = "就绪"
    @Published var log: [String] = []

    private var session: NFCTagReaderSession?

    private func appendLog(_ msg: String) {
        log.append(msg)
        if log.count > 300 { log.removeFirst() }
        print("[NFC] \(msg)")
    }

    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    func startUnlock() {
        guard isAvailable else {
            appendLog("此设备不支持 NFC 标签读取")
            statusText = "设备不支持 NFC"
            return
        }
        let settings = SettingsManager.shared
        guard settings.isConfigured(), settings.deviceId != 0 else {
            appendLog("未配置 chainKey/deviceId，请先登录拉取凭证")
            statusText = "请先登录拉取凭证"
            return
        }

        let s = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil)
        s?.alertMessage = "请将手机贴近门锁感应区"
        session = s
        statusText = "请碰锁..."
        appendLog("开始 NFC 会话")
        s?.begin()
    }

    // ─── 把两种 tag case 的 sendMiFareCommand 统一成一个闭包 ───
    private func makeSender(for tag: NFCTag) -> ((Data) async throws -> Data)? {
        switch tag {
        case .iso14443(let t):
            return { data in
                try await withCheckedThrowingContinuation { cont in
                    t.sendMiFareCommand(commandPacket: data) { resp, err in
                        if let err = err { cont.resume(throwing: err) } else { cont.resume(returning: resp) }
                    }
                }
            }
        case .miFare(let t):
            return { data in
                try await withCheckedThrowingContinuation { cont in
                    t.sendMiFareCommand(commandPacket: data) { resp, err in
                        if let err = err { cont.resume(throwing: err) } else { cont.resume(returning: resp) }
                    }
                }
            }
        default:
            return nil
        }
    }

    private func identifierHex(of tag: NFCTag) -> String {
        let data: Data?
        switch tag {
        case .iso14443(let t): data = t.identifier
        case .miFare(let t): data = t.identifier
        case .felica(let t): data = t.currentIDm
        case .iso15693(let t): data = t.identifier
        @unknown default: data = nil
        }
        guard let d = data else { return "?" }
        return d.map { String(format: "%02X", $0) }.joined()
    }

    private func connectAsync(session: NFCTagReaderSession, tag: NFCTag) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.connect(to: tag) { error in
                if let error = error { cont.resume(throwing: error) } else { cont.resume(returning: ()) }
            }
        }
    }

    private func handle(tag: NFCTag, session: NFCTagReaderSession) async {
        guard let send = makeSender(for: tag) else {
            appendLog("标签不是 ISO14443-A / MIFARE 类型 (techList 不匹配)")
            session.invalidate(errorMessage: "不支持的标签类型")
            statusText = "不支持的标签类型"
            return
        }

        do {
            try await connectAsync(session: session, tag: tag)
        } catch {
            appendLog("连接标签失败: \(error.localizedDescription)")
            session.invalidate(errorMessage: "连接标签失败，请重试")
            statusText = "连接标签失败"
            return
        }

        appendLog("标签 UID: \(identifierHex(of: tag))")

        let settings = SettingsManager.shared
        let cmd = DoorCrypto.buildNfcOpenCommand(deviceId: settings.deviceId, projectId: settings.projectId, chainKeyHex: settings.chainKey)
        appendLog("→ 指令(\(cmd.count)B): \(DoorCrypto.bytesToHex(cmd))")

        var response: [UInt8]?
        // 3 次重试: NFC 通信容易被标签移动打断，与 Android 版策略一致
        for attempt in 1...3 {
            do {
                let respData = try await send(Data(cmd))
                let bytes = [UInt8](respData)
                appendLog("[第\(attempt)次] ← 响应(\(bytes.count)B): \(DoorCrypto.bytesToHex(bytes))")
                if bytes.first == 0xB1 {
                    response = bytes
                    break
                }
                appendLog("[第\(attempt)次] 响应不是合法 0xB1 帧")
            } catch {
                appendLog("[第\(attempt)次] 失败: \(error.localizedDescription)")
            }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        guard let resp = response else {
            appendLog("✗ 3 次均未获得合法 0xB1 响应")
            session.invalidate(errorMessage: "门锁无响应，请重试")
            statusText = "门锁无响应"
            return
        }

        let result = DoorCrypto.parseNfcResponse(resp, deviceId: settings.deviceId)
        if result.error != nil { appendLog("✗ 解析: \(result.error!)") }
        guard result.success else {
            let msg = result.message.isEmpty ? (result.error ?? "开门失败") : result.message
            appendLog("✗ 开锁失败: \(msg) (resultCode=\(result.resultCode))")
            session.invalidate(errorMessage: msg)
            statusText = "开门失败: \(msg)"
            return
        }

        // 密钥轮换: 锁返回新 chainKey，必须保存，否则下次开门会用旧钥匙失败
        if let newKey = result.newChainKeyHex, !newKey.isEmpty,
           newKey.lowercased() != String(repeating: "0", count: newKey.count) {
            appendLog("凭证轮换: \(settings.chainKey.prefix(12))… → \(newKey.prefix(12))…")
            settings.chainKey = newKey.lowercased()
        }

        appendLog("✓ \(result.message) (seq=\(result.seq.map(String.init) ?? "nil"))")
        statusText = result.doorAlreadyOpen ? "门已打开 🔓" : "开门成功 🔓"
        session.alertMessage = statusText
        session.invalidate()
    }
}

extension DoorNFCManager: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        Task { @MainActor in self.appendLog("NFC 会话已激活，等待碰锁...") }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.appendLog("会话结束: \(error.localizedDescription)")
            self.session = nil
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        Task { @MainActor in
            await self.handle(tag: tag, session: session)
        }
    }
}
