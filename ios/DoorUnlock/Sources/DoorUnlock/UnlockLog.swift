import Foundation

/// 开锁记录: 每次开门的时间、方式、结果、耗时。只存在本机 UserDefaults，最多 200 条。
/// 用途: 自己回看 + 对比蓝牙/NFC 的实际耗时，调速度有数据可依。
struct UnlockRecord: Codable, Identifiable, Equatable {
    enum Method: String, Codable { case ble, nfc }

    var id = UUID()
    var date: Date
    var method: Method
    var success: Bool
    var detail: String        // 成功: "开门成功" / "门已打开"；失败: 失败原因
    var duration: Double      // 秒
}

@MainActor
final class UnlockLog: ObservableObject {
    static let shared = UnlockLog()
    static let capacity = 200
    private let key = "unlock_records"

    @Published private(set) var records: [UnlockRecord] = []   // 新的在前

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UnlockRecord].self, from: data) {
            records = decoded
        }
    }

    func add(method: UnlockRecord.Method, success: Bool, detail: String, duration: TimeInterval) {
        records.insert(UnlockRecord(date: Date(), method: method, success: success,
                                    detail: detail, duration: duration), at: 0)
        if records.count > Self.capacity { records.removeLast(records.count - Self.capacity) }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    var hasSuccess: Bool { records.contains { $0.success } }

    /// 最近 20 次成功开门的平均耗时
    func averageDuration(_ method: UnlockRecord.Method) -> Double? {
        let xs = records.filter { $0.success && $0.method == method }.prefix(20).map(\.duration)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
