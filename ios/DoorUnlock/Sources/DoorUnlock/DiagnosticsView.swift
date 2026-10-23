import SwiftUI

/// 日志脱敏: 复制出去的日志要能直接贴到 issue 里。
/// 蓝牙/NFC 帧里的密文是用设备号派生的密钥 RC4 加密的，设备号一旦公开就能解出来，
/// 所以长十六进制串一律只留开头几字节；手机号也打码。
enum LogRedactor {
    static func redact(_ text: String) -> String {
        var out = text
        out = out.replacingOccurrences(
            of: "[0-9A-Fa-f]{24,}",
            with: "<hex 已打码>", options: .regularExpression)
        out = out.replacingOccurrences(
            of: "(?<!\\d)(1\\d{2})\\d{4}(\\d{4})(?!\\d)",
            with: "$1****$2", options: .regularExpression)
        return out
    }
}

/// 诊断: 蓝牙 / NFC / 网络三种日志合并在一页，分段切换。
struct DiagnosticsView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager

    private enum Kind: String, CaseIterable, Identifiable {
        case ble = "蓝牙", nfc = "NFC", net = "网络"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .ble
    @State private var copied = false
    @State private var refresh = 0   // 网络日志是 static 的，不会自动刷新界面

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                let lines = currentLines
                if lines.isEmpty {
                    Text("暂无日志").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } footer: {
                Text("「复制」会自动给长十六进制串和手机号打码，可以直接贴到 issue。屏幕上显示的是原文，截图前注意。")
            }
        }
        .id(refresh)
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(copied ? "已复制" : "复制") {
                    UIPasteboard.general.string = LogRedactor.redact(currentLines.joined(separator: "\n"))
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                Button("清空", role: .destructive) { clear() }
            }
        }
    }

    private var currentLines: [String] {
        switch kind {
        case .ble: return Array(ble.log.suffix(80))
        case .nfc: return Array(nfc.log.suffix(80))
        case .net: return Array(ServerApi.debugLog.suffix(100))
        }
    }

    private func clear() {
        switch kind {
        case .ble: ble.log.removeAll()
        case .nfc: nfc.log.removeAll()
        case .net: ServerApi.debugLog.removeAll(); refresh += 1
        }
    }
}
