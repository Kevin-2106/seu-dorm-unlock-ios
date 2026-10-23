import Foundation
import CoreBluetooth

/// BLE 开门管理器 (移植自 Android 版 BleUnlockManager.kt)
///
/// 直连优化: CoreBluetooth 不暴露真实 MAC，但 `CBPeripheral.identifier` 是同一台 iOS 设备上
/// 对同一个外设稳定不变的 UUID。第一次成功连接后缓存这个 UUID，下次开门先用
/// `retrievePeripherals(withIdentifiers:)` 直连，跳过几秒的广播扫描；拿不到(比如换了台
/// iOS 设备、或系统缓存被清)再退回正常扫描。这个 UUID 是设备本地的，不放进可跨设备
/// 分享的配置码 (ConfigCode.swift)。
@MainActor
final class DoorBLEManager: NSObject, ObservableObject {

    enum State { case idle, scanning, connecting, unlocking, success, failed }

    @Published var state: State = .idle
    @Published var statusText: String = "就绪"
    @Published var log: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var readChar: CBCharacteristic?

    private let serviceUUID = CBUUID(string: DoorCrypto.SERVICE_UUID)
    private let writeUUID = CBUUID(string: DoorCrypto.WRITE_UUID)
    private let readUUID = CBUUID(string: DoorCrypto.READ_UUID)

    // ─── 各阶段的一次性续体 (对应 Android 版的 CompletableDeferred) ───
    private var scanContinuation: CheckedContinuation<CBPeripheral?, Never>?
    private var connectContinuation: CheckedContinuation<Bool, Never>?
    private var servicesContinuation: CheckedContinuation<Bool, Never>?
    private var notifyContinuation: CheckedContinuation<Bool, Never>?
    private var responseContinuation: CheckedContinuation<[UInt8]?, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    private func appendLog(_ msg: String) {
        log.append(msg)
        if log.count > 300 { log.removeFirst() }
        print("[BLE] \(msg)")
    }

    // ─── 开门主流程 ───
    func unlock() async {
        state = .unlocking
        statusText = "准备中..."
        let settings = SettingsManager.shared

        guard central.state == .poweredOn else {
            fail("蓝牙未开启")
            return
        }

        appendLog("当前参数: deviceId=\(settings.deviceId), projectId=\(settings.projectId), credId=\(settings.credentialId), chainKey长度=\(settings.chainKey.count)")

        state = .scanning
        var p: CBPeripheral?
        var usedCache = false

        // 先试缓存的 peripheral UUID 直连，不用等几秒广播扫描
        if !settings.cachedPeripheralID.isEmpty, let uuid = UUID(uuidString: settings.cachedPeripheralID) {
            statusText = "直连门锁..."
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let cached = known.first {
                appendLog("命中缓存 UUID，直连: \(uuid.uuidString)")
                p = cached
                usedCache = true
            } else {
                appendLog("缓存 UUID 失效 (系统已不认识这个外设)，回退扫描")
            }
        }

        if p == nil {
            statusText = "扫描门锁..."
            p = await scanDevice(targetName: settings.bleName)
            usedCache = false
        }

        guard var device = p else {
            fail("未发现门锁设备 (XN-\(settings.deviceId))")
            return
        }

        statusText = "连接门锁..."
        state = .connecting
        var connected = await connectAndDiscover(device)

        // 缓存直连失败 (设备不在附近了/换了台锁)：退回一次正常扫描再试，而不是直接报错
        if !connected && usedCache {
            appendLog("缓存直连失败，回退扫描重试...")
            central.cancelPeripheralConnection(device) // 清掉这次失败的连接尝试，避免悬着
            settings.cachedPeripheralID = ""
            statusText = "扫描门锁..."
            state = .scanning
            guard let fresh = await scanDevice(targetName: settings.bleName) else {
                fail("未发现门锁设备 (XN-\(settings.deviceId))")
                return
            }
            device = fresh
            statusText = "连接门锁..."
            state = .connecting
            connected = await connectAndDiscover(device)
        }

        guard connected else {
            fail("连接或服务发现失败")
            return
        }
        settings.cachedPeripheralID = device.identifier.uuidString

        appendLog("已连接门锁，开始开门流程")

        do {
            try await runUnlockSequence()
        } catch {
            fail(error.localizedDescription)
        }
        disconnect()
    }

    private func fail(_ message: String) {
        appendLog("失败: \(message)")
        state = .failed
        statusText = message
        disconnect()
    }

    private func runUnlockSequence() async throws {
        let settings = SettingsManager.shared

        // Step 1: 凭证头 (0x74)
        statusText = "发送凭证..."
        let headPkt = DoorCrypto.buildCredentialHead(
            chainKeyHex: settings.chainKey, deviceId: settings.deviceId, projectId: settings.projectId)
        guard let headResp = await sendPacketAndWait(headPkt) else { throw UnlockError.message("0x74 命令超时") }
        let headResult = DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(headResp), deviceId: settings.deviceId)
        guard headResult.success else { throw UnlockError.message("0x74 解析失败: \(headResult.error ?? "")") }
        let ran = headResult.ran
        appendLog("Step 1 ok, ran=0x\(String(UInt32(bitPattern: ran), radix: 16).uppercased())")

        // Step 2: 凭证分包 (0x75)
        statusText = "传输凭证..."
        let packs = DoorCrypto.buildCredentialPacks(
            chainKeyHex: settings.chainKey, ran: ran, deviceId: settings.deviceId, projectId: settings.projectId)
        for (i, pack) in packs.enumerated() {
            guard let resp = await sendPacketAndWait(pack) else { throw UnlockError.message("0x75 分包 \(i + 1) 超时") }
            let result = DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(resp), deviceId: settings.deviceId)
            guard result.isSuccess else { throw UnlockError.message("0x75 分包 \(i + 1) 失败") }
        }
        appendLog("Step 2 ok (\(packs.count) 包)")

        // Step 3: 开锁命令 (0x78)
        statusText = "开锁中..."
        guard let unlockResp = await sendPacketAndWait(DoorCrypto.buildUnlockCommand(deviceId: settings.deviceId)) else {
            throw UnlockError.message("0x78 命令超时")
        }
        let unlockResult = DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(unlockResp), deviceId: settings.deviceId)
        appendLog("0x78 响应: resultCode=\(unlockResult.resultCode)")

        if unlockResult.isSuccess {
            appendLog("开门成功! 🔓")
            state = .success
            statusText = unlockResult.doorAlreadyOpen ? "门已打开 🔓" : "开门成功! 🔓"
        } else if unlockResult.needUpdateKey {
            appendLog("门已开, 后台更新密钥...")
            state = .success
            statusText = "开门成功 🔓"
            if let newKey = await updateChainKey(), !newKey.allSatisfy({ $0 == "0" }) {
                settings.chainKey = newKey
                appendLog("chainKey 已更新")
            }
        } else if unlockResult.resultCode == 25 {
            appendLog("离线次数已用完, 从服务器刷新凭证...")
            guard settings.isLoggedIn() else { throw UnlockError.message("离线次数已用完\n请在设置中登录后重试") }
            statusText = "刷新凭证中..."
            guard await refreshChainKeyFromServer() else { throw UnlockError.message("刷新凭证失败, 请用原 App 开门一次") }
            try await retryUnlockWithNewKey()
        } else if unlockResult.resultCode == 24 {
            appendLog("凭证过期(0x18), 从服务器刷新凭证...")
            statusText = "登录服务器..."
            guard await ensureLoggedIn() else { throw UnlockError.message("凭证已过期\n请在设置中登录后重试") }
            statusText = "刷新凭证中..."
            guard await refreshChainKeyFromServer() else { throw UnlockError.message("刷新凭证失败, 请用原 App 开门一次") }
            try await retryUnlockWithNewKey()
        } else {
            throw UnlockError.message("开锁失败: 错误码 \(unlockResult.resultCode)")
        }
    }

    enum UnlockError: Error, LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    // ─── 密钥更新 (0x76 → N×0x77) ───
    private func updateChainKey() async -> String? {
        let settings = SettingsManager.shared
        guard let resp = await sendPacketAndWait(
            DoorCrypto.buildRechainKeyRequest(credentialId: settings.credentialId, deviceId: settings.deviceId)
        ) else { return nil }
        let result = DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(resp), deviceId: settings.deviceId)
        guard result.isSuccess else { return nil }

        appendLog("密钥分包: \(result.packCount), 总长: \(result.totalLength)")
        var packs: [DoorCrypto.PackData] = []
        for i in 0..<result.packCount {
            guard let readResp = await sendPacketAndWait(DoorCrypto.buildPackReadRequest(packIndex: i, deviceId: settings.deviceId))
            else { return nil }
            let readResult = DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(readResp), deviceId: settings.deviceId)
            guard readResult.success else { return nil }
            packs.append(DoorCrypto.PackData(packIndex: readResult.packIndex, resultData: readResult.resultData))
        }

        do {
            let assembled = try DoorCrypto.assembleChainKey(packs, expectedLength: result.totalLength, expectedCrc: UInt8(result.crc8Val))
            return DoorCrypto.bytesToHex(assembled)
        } catch {
            appendLog("chainKey 拼装失败: \(error.localizedDescription)")
            return nil
        }
    }

    // ─── 从服务器刷新 chainKey (错误 24/25 自动恢复) ───
    private func ensureLoggedIn() async -> Bool {
        let settings = SettingsManager.shared
        if settings.isLoggedIn() { return true }
        let phone = settings.loginPhone
        let pwd = settings.loginPassword
        guard !phone.isEmpty, !pwd.isEmpty else { return false }
        appendLog("尝试自动登录: \(phone)")
        let result = await ServerApi.login(phone: phone, password: pwd)
        if result.success { appendLog("自动登录成功"); return true }
        appendLog("自动登录失败: \(result.error)")
        return false
    }

    private func refreshChainKeyFromServer() async -> Bool {
        do {
            let addr = try await ServerApi.fetchAddress()
            guard !addr.chainKey.isEmpty else { return false }
            let settings = SettingsManager.shared
            settings.chainKey = addr.chainKey
            settings.credentialId = addr.credentialId
            appendLog("已从服务器获取新 chainKey: \(addr.chainKey.prefix(16))...")
            return true
        } catch {
            appendLog("刷新凭证异常: \(error.localizedDescription)")
            return false
        }
    }

    private func retryUnlockWithNewKey() async throws {
        let settings = SettingsManager.shared
        appendLog("使用新 chainKey 重试开门...")
        let head2 = DoorCrypto.buildCredentialHead(chainKeyHex: settings.chainKey, deviceId: settings.deviceId, projectId: settings.projectId)
        guard let headR2 = await sendPacketAndWait(head2) else { throw UnlockError.message("重试 0x74 超时") }
        let headP2 = DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(headR2), deviceId: settings.deviceId)
        guard headP2.success else { throw UnlockError.message("重试 0x74 失败") }

        let packs2 = DoorCrypto.buildCredentialPacks(chainKeyHex: settings.chainKey, ran: headP2.ran, deviceId: settings.deviceId, projectId: settings.projectId)
        for (i, p) in packs2.enumerated() {
            guard let r = await sendPacketAndWait(p) else { throw UnlockError.message("重试 0x75 分包\(i + 1) 超时") }
            guard DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(r), deviceId: settings.deviceId).isSuccess else {
                throw UnlockError.message("重试 0x75 分包\(i + 1) 失败")
            }
        }

        guard let unl2 = await sendPacketAndWait(DoorCrypto.buildUnlockCommand(deviceId: settings.deviceId)) else {
            throw UnlockError.message("重试 0x78 超时")
        }
        let unlR2 = DoorCrypto.parseResponse(hexData: DoorCrypto.bytesToHex(unl2), deviceId: settings.deviceId)
        if unlR2.isSuccess || unlR2.needUpdateKey {
            appendLog("刷新凭证后开门成功! 🔓")
            state = .success
            statusText = "开门成功 🔓"
        } else {
            throw UnlockError.message("重试失败: 错误码 \(unlR2.resultCode)")
        }
    }

    // ─── BLE 底层 (事件驱动) ───

    private func scanDevice(targetName: String) async -> CBPeripheral? {
        await withCheckedContinuation { cont in
            self.scanContinuation = cont
            self.appendLog("开始扫描 BLE 设备 (目标: \(targetName)) ...")
            self.central.scanForPeripherals(withServices: nil, options: nil)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.central.stopScan()
                if let c = self.scanContinuation {
                    self.scanContinuation = nil
                    c.resume(returning: nil)
                }
            }
        }
    }

    private func connectAndDiscover(_ p: CBPeripheral) async -> Bool {
        peripheral = p
        p.delegate = self

        let connected = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.connectContinuation = cont
            self.central.connect(p, options: nil)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let c = self.connectContinuation {
                    self.connectContinuation = nil
                    c.resume(returning: false)
                }
            }
        }
        guard connected else { return false }

        let discovered = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.servicesContinuation = cont
            p.discoverServices([serviceUUID])
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let c = self.servicesContinuation {
                    self.servicesContinuation = nil
                    c.resume(returning: false)
                }
            }
        }
        guard discovered, writeChar != nil, readChar != nil else { return false }

        guard let rc = readChar else { return false }
        let notified = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.notifyContinuation = cont
            p.setNotifyValue(true, for: rc)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let c = self.notifyContinuation {
                    self.notifyContinuation = nil
                    c.resume(returning: false)
                    self.appendLog("CCCD 写入超时，尝试继续...")
                }
            }
        }
        if notified { appendLog("CCCD 通知已启用") }
        appendLog("BLE 连接就绪")
        return true
    }

    private func sendPacketAndWait(_ packet: [UInt8]) async -> [UInt8]? {
        guard let p = peripheral, let wc = writeChar else { return nil }
        return await withCheckedContinuation { cont in
            self.responseContinuation = cont
            p.writeValue(Data(packet), for: wc, type: .withResponse)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let c = self.responseContinuation {
                    self.responseContinuation = nil
                    self.appendLog("等待响应超时")
                    c.resume(returning: nil)
                }
            }
        }
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        readChar = nil
    }

    func cancel() {
        disconnect()
        state = .idle
        statusText = "就绪"
    }
}

extension DoorBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.appendLog("蓝牙状态: \(central.state.rawValue)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        Task { @MainActor in
            if !name.isEmpty { self.appendLog("扫描发现: [\(name)]") }
            guard name == SettingsManager.shared.bleName else { return }
            self.appendLog(">> 命中目标: \(name)")
            self.central.stopScan()
            if let c = self.scanContinuation {
                self.scanContinuation = nil
                c.resume(returning: peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.appendLog("已连接, 发现服务...")
            if let c = self.connectContinuation {
                self.connectContinuation = nil
                c.resume(returning: true)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.appendLog("连接失败: \(error?.localizedDescription ?? "")")
            if let c = self.connectContinuation {
                self.connectContinuation = nil
                c.resume(returning: false)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.appendLog("已断开")
        }
    }
}

extension DoorBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: DoorCrypto.SERVICE_UUID) }) else {
            Task { @MainActor in
                self.appendLog("未找到 BLE 服务")
                if let c = self.servicesContinuation { self.servicesContinuation = nil; c.resume(returning: false) }
            }
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: DoorCrypto.WRITE_UUID), CBUUID(string: DoorCrypto.READ_UUID)], for: service)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for c in service.characteristics ?? [] {
                if c.uuid == CBUUID(string: DoorCrypto.WRITE_UUID) { self.writeChar = c }
                if c.uuid == CBUUID(string: DoorCrypto.READ_UUID) { self.readChar = c }
            }
            let ok = self.writeChar != nil && self.readChar != nil
            if !ok { self.appendLog("未找到 write/read characteristic") }
            if let cont = self.servicesContinuation { self.servicesContinuation = nil; cont.resume(returning: ok) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let e = error { self.appendLog("CCCD 写入失败: \(e.localizedDescription)") }
            else { self.appendLog("CCCD 写入成功") }
            if let c = self.notifyContinuation { self.notifyContinuation = nil; c.resume(returning: error == nil) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, data.count >= 20 else { return }
        let bytes = [UInt8](data)
        Task { @MainActor in
            if let c = self.responseContinuation {
                self.responseContinuation = nil
                c.resume(returning: bytes)
            }
        }
    }
}
