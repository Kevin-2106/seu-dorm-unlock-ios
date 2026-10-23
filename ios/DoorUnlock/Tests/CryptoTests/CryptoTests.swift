import XCTest
@testable import DoorCrypto

/// 期望值来自上游 Kotlin 实现 (Crypto.kt) 跑出的测试向量，与 Swift 移植逐字节比对一致。
/// 改协议层时这些测试挂了，说明和上游不再等价。
final class CryptoTests: XCTestCase {
    let deviceId: Int32 = 2282625
    let chainKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    private func hex(_ b: [UInt8]) -> String { DoorCrypto.bytesToHex(b) }

    func testDeriveDeviceKey() {
        XCTAssertEqual(hex(DoorCrypto.deriveDeviceKey(0)), "E6D258DF46C31FCCE0140F64A83A7D32")
        XCTAssertEqual(hex(DoorCrypto.deriveDeviceKey(1)), "E4D258DF44C31FCCE2140F64AA3A7D32")
        XCTAssertEqual(hex(DoorCrypto.deriveDeviceKey(deviceId)), "E5525CDF45EB5BCCE2BC0F64AA3A7932")
        XCTAssertEqual(hex(DoorCrypto.deriveDeviceKey(-1)), "25435453D9EB40509AABBDC8FE6D788E")
    }

    func testCrc8() {
        XCTAssertEqual(DoorCrypto.crc8([]), 0)
        XCTAssertEqual(DoorCrypto.crc8([0x00]), 0)
        XCTAssertEqual(DoorCrypto.crc8([1, 2, 3, 4]), 244)
        XCTAssertEqual(DoorCrypto.crc8((0..<16).map { UInt8($0) }), 60)
    }

    func testRc4() {
        let key = DoorCrypto.deriveDeviceKey(deviceId)
        let data: [UInt8] = (0..<16).map { UInt8(($0 * 7) & 0xFF) }
        let enc = DoorCrypto.rc4(data, key: key)
        XCTAssertEqual(hex(enc), "1FE81844ADC4B8AF55C53CDFCE1C6C08")
        XCTAssertEqual(DoorCrypto.rc4(enc, key: key), data)
    }

    func testBleFrames() {
        XCTAssertEqual(
            hex(DoorCrypto.buildCredentialHead(chainKeyHex: chainKey, deviceId: deviceId, projectId: 1)),
            "14007437EF1581B1E7929E6DFA7A929A470E61C4")
        let packs = DoorCrypto.buildCredentialPacks(chainKeyHex: chainKey, ran: 0x11223344, deviceId: deviceId, projectId: 1)
        XCTAssertEqual(packs.map(hex), [
            "1400751FAB2573A0E6929E6DFB59D7FDCEA5AC9A",
            "1400751E001772F4801B35A0157BB1DF2087CA74",
            "1400751D22F95092A2F517C63795929A470E6104",
        ])
        XCTAssertEqual(hex(DoorCrypto.buildUnlockCommand(deviceId: deviceId)),
                       "1400781FEF1651B1E7929E6DFA7A929A470E6100")
        XCTAssertEqual(hex(DoorCrypto.buildRechainKeyRequest(credentialId: 777, deviceId: deviceId)),
                       "14007616EC1651B1E7929E6DFA7A929A470E6111")
        XCTAssertEqual(hex(DoorCrypto.buildPackReadRequest(packIndex: 0, deviceId: deviceId)),
                       "1400771FEF1651B1E7929E6DFA7A929A470E6100")
    }

    func testNfcOpenCommand() {
        XCTAssertEqual(
            hex(DoorCrypto.buildNfcOpenCommand(deviceId: deviceId, projectId: 1, chainKeyHex: chainKey)),
            "B10D241EEF1651B0C4D7F9E451B77D9B644B06E421739D5CADE5589BC5F72EEBCF29A316EEC014BD")
    }

    func testNfcResponseRoundTrip() {
        let newKey: [UInt8] = (0..<32).map { UInt8(0xA0 + $0) }
        let plain: [UInt8] = [0, 0, 0, 0] + newKey + [0x44, 0x33, 0x22, 0x11]
        let cipher = DoorCrypto.rc4(plain, key: DoorCrypto.deriveDeviceKey(deviceId))
        var frame: [UInt8] = [0xB1, 0x0D, UInt8(cipher.count)] + cipher
        frame.append(DoorCrypto.crc8([0x0D, UInt8(cipher.count)] + plain))
        XCTAssertEqual(hex(frame),
            "B10D281FEF16511146303DC95FDC3532EEA4CAC12710DDED3F128CA6DB8C765255D67F23F8B3445DF48CE12A")
        let r = DoorCrypto.parseNfcResponse(frame, deviceId: deviceId)
        XCTAssertTrue(r.success)
        XCTAssertEqual(r.resultCode, 0)
        XCTAssertEqual(r.newChainKeyHex, hex(newKey))
        XCTAssertEqual(r.seq, 0x11223344)
    }

    func testNfcResponseRejectsBadCrc() {
        let plain: [UInt8] = [0, 0, 0, 0] + [UInt8](repeating: 1, count: 32) + [1, 2, 3, 4]
        let cipher = DoorCrypto.rc4(plain, key: DoorCrypto.deriveDeviceKey(deviceId))
        let frame: [UInt8] = [0xB1, 0x0D, UInt8(cipher.count)] + cipher + [0x00]
        XCTAssertNil(DoorCrypto.parseNfcResponse(frame, deviceId: deviceId).newChainKeyHex)
    }
}
