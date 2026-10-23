import SwiftUI

/// 设置页：账号登录、门锁参数、配置码导入导出、各种调试日志。
/// 首页只留开门按钮，细节都在这。
struct SettingsView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager
    @Environment(\.dismiss) private var dismiss

    @State private var deviceIdText = ""
    @State private var projectIdText = ""
    @State private var credentialIdText = ""
    @State private var chainKeyText = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var fetchStatus = ""
    @State private var isFetching = false
    @State private var configStatus = ""

    var body: some View {
        NavigationView {
            Form {
                Section("账号登录 (用于获取/刷新凭证)") {
                    TextField("手机号", text: $phone).keyboardType(.phonePad)
                    SecureField("密码", text: $password)
                    Button(isFetching ? "拉取中..." : "登录并拉取门锁凭证") {
                        Task { await loginAndFetch() }
                    }
                    .disabled(isFetching || phone.isEmpty || password.isEmpty)
                    if !fetchStatus.isEmpty {
                        Text(fetchStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("导出配置码到剪贴板") {
                        ShareableConfig.fromCurrentSettings().copyToPasteboard()
                        configStatus = "✓ 已复制，去另一台设备粘贴导入"
                    }
                    .disabled(!SettingsManager.shared.isConfigured())

                    Button("从剪贴板导入配置码") {
                        if let cfg = ShareableConfig.fromPasteboard() {
                            cfg.apply()
                            loadSettings()
                            configStatus = "✓ 已导入 device=\(cfg.deviceId)"
                        } else {
                            configStatus = "剪贴板里没有有效的配置码"
                        }
                    }
                    if !configStatus.isEmpty {
                        Text(configStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("配置码 (同账号多设备共享)")
                } footer: {
                    Text("配置码只是已拉取到的开门凭据，不含账号密码。在第一台设备登录拉取后，\n其余设备直接导出/导入配置码即可，不用再重新登录(避免反复顶掉官方 app 的会话)。")
                }

                Section("门锁参数 (登录拉取/导入配置码后自动填入，可手动修改)") {
                    TextField("设备ID (deviceId)", text: $deviceIdText).keyboardType(.numberPad)
                    TextField("项目ID (projectId)", text: $projectIdText).keyboardType(.numberPad)
                    TextField("凭证ID (credentialId)", text: $credentialIdText).keyboardType(.numberPad)
                    TextField("chainKey (64位hex)", text: $chainKeyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存参数") { saveSettings() }
                }

                Section("NFC 通讯日志") {
                    ForEach(Array(nfc.log.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("网络日志 (调试用，排查登录/拉凭证问题)") {
                    ForEach(Array(ServerApi.debugLog.suffix(100).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("蓝牙通讯日志") {
                    ForEach(ble.log.suffix(50), id: \.self) { line in
                        Text(line).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: loadSettings)
        }
    }

    private func loadSettings() {
        let s = SettingsManager.shared
        deviceIdText = s.deviceId == 0 ? "" : String(s.deviceId)
        projectIdText = s.projectId == 0 ? "" : String(s.projectId)
        credentialIdText = s.credentialId == 0 ? "" : String(s.credentialId)
        chainKeyText = s.chainKey
        phone = s.loginPhone
    }

    private func saveSettings() {
        let s = SettingsManager.shared
        s.deviceId = Int32(deviceIdText) ?? 0
        s.projectId = Int32(projectIdText) ?? 0
        s.credentialId = Int32(credentialIdText) ?? 0
        s.chainKey = chainKeyText
    }

    private func loginAndFetch() async {
        isFetching = true
        fetchStatus = "登录中..."
        let s = SettingsManager.shared
        s.loginPhone = phone
        s.loginPassword = password

        let result = await ServerApi.login(phone: phone, password: password)
        guard result.success else {
            fetchStatus = "登录失败: \(result.error)"
            isFetching = false
            return
        }

        fetchStatus = "登录成功，拉取门锁信息..."
        do {
            let addr = try await ServerApi.fetchAddress()
            guard addr.deviceId != 0 else {
                fetchStatus = "未找到绑定的门锁"
                isFetching = false
                return
            }
            s.deviceId = addr.deviceId
            s.deviceMac = addr.mac
            s.credentialId = addr.credentialId
            s.chainKey = addr.chainKey
            // ★ projectId 不是服务器直接给的字段，是 Android 版"自动获取参数"按钮的隐藏逻辑：
            //   projectId 其实就是登录时拿到的 serverAppId，不是用户瞎填的。
            s.projectId = s.serverAppId.isEmpty ? s.projectId : (Int32(s.serverAppId) ?? s.projectId)
            loadSettings()
            fetchStatus = "✓ 已获取: \(addr.buildingName)\(addr.floorName)\(addr.roomName) (device=\(addr.deviceId), projectId=\(s.projectId))"
        } catch {
            fetchStatus = "拉取失败: \(error.localizedDescription)"
        }
        isFetching = false
    }
}
