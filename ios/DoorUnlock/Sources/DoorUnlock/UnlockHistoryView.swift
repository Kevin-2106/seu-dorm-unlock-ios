import SwiftUI

/// 设置 → 开锁记录
struct UnlockHistoryView: View {
    @ObservedObject private var log = UnlockLog.shared
    @State private var confirmClear = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        List {
            if log.records.isEmpty {
                Text("还没有记录").foregroundStyle(.secondary)
            } else {
                Section {
                    averageRow("蓝牙", .ble)
                    averageRow("NFC", .nfc)
                } header: {
                    Text("最近 20 次成功的平均耗时")
                }
                Section {
                    ForEach(log.records) { r in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.success ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.detail)
                                Text(Self.formatter.string(from: r.date) + " · " + (r.method == .ble ? "蓝牙" : "NFC"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f 秒", r.duration))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("只保存在本机，最多 \(UnlockLog.capacity) 条。")
                }
            }
        }
        .navigationTitle("开锁记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清空", role: .destructive) { confirmClear = true }
                    .disabled(log.records.isEmpty)
            }
        }
        .confirmationDialog("清空所有开锁记录?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { log.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private func averageRow(_ title: String, _ m: UnlockRecord.Method) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(log.averageDuration(m).map { String(format: "%.1f 秒", $0) } ?? "—")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
