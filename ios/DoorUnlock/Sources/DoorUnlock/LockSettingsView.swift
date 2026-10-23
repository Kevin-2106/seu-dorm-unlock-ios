import SwiftUI

/// 门锁: 账号登录拉取凭据、配置码导入导出，手动编辑参数收在「高级」里。
struct LockSettingsView: View {
    @State private var phone: String
    @State private var password = ""
    @State private var fetchStatus = ""
    @State private var isFetching = false
    @State private var configStatus = ""

    init() {
        _phone = State(initialValue: SettingsManager.shared.loginPhone)
    }

    var body: some View {
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

            Section {
                NavigationLink("手动编辑门锁参数") { LockAdvancedView() }
            } footer: {
                Text("一般不需要。登录拉取或导入配置码后参数会自动填好。")
            }
        }
        .navigationTitle("门锁")
        .navigationBarTitleDisplayMode(.inline)
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
            fetchStatus = "✓ 已获取: \(addr.buildingName)\(addr.floorName)\(addr.roomName) (device=\(addr.deviceId), projectId=\(s.projectId))"
        } catch {
            fetchStatus = "拉取失败: \(error.localizedDescription)"
        }
        isFetching = false
    }
}

/// 手动编辑门锁参数。改错 chainKey 会导致开不了门，所以保存前要确认。
struct LockAdvancedView: View {
    @State private var deviceIdText: String
    @State private var projectIdText: String
    @State private var credentialIdText: String
    @State private var chainKeyText: String
    @State private var saveStatus = ""
    @State private var confirming = false

    /// 在视图创建时就把已保存的参数灌进 @State，而不是等 onAppear:
    /// Form 里的 TextField 首次渲染用空字符串，之后 state 更新不一定触发重绘，
    /// 表现为"点一下输入框才显示内容"。
    init() {
        let s = SettingsManager.shared
        _deviceIdText = State(initialValue: s.deviceId == 0 ? "" : String(s.deviceId))
        _projectIdText = State(initialValue: s.projectId == 0 ? "" : String(s.projectId))
        _credentialIdText = State(initialValue: s.credentialId == 0 ? "" : String(s.credentialId))
        _chainKeyText = State(initialValue: s.chainKey)
    }

    var body: some View {
        Form {
            Section {
                TextField("设备ID (deviceId)", text: $deviceIdText).keyboardType(.numberPad)
                TextField("项目ID (projectId)", text: $projectIdText).keyboardType(.numberPad)
                TextField("凭证ID (credentialId)", text: $credentialIdText).keyboardType(.numberPad)
                TextField("chainKey (64位hex)", text: $chainKeyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存参数") { confirming = true }
                if !saveStatus.isEmpty {
                    Text(saveStatus).font(.footnote).foregroundStyle(.green)
                }
            } footer: {
                Text("chainKey 相当于这把锁的钥匙，不要发给别人。改错会导致开不了门，可重新登录拉取恢复。")
            }
        }
        .navigationTitle("门锁参数")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .confirmationDialog("覆盖当前门锁参数?", isPresented: $confirming, titleVisibility: .visible) {
            Button("保存", role: .destructive) { save() }
            Button("取消", role: .cancel) {}
        }
    }

    private func load() {
        let s = SettingsManager.shared
        deviceIdText = s.deviceId == 0 ? "" : String(s.deviceId)
        projectIdText = s.projectId == 0 ? "" : String(s.projectId)
        credentialIdText = s.credentialId == 0 ? "" : String(s.credentialId)
        chainKeyText = s.chainKey
    }

    private func save() {
        let s = SettingsManager.shared
        s.deviceId = Int32(deviceIdText) ?? 0
        s.projectId = Int32(projectIdText) ?? 0
        s.credentialId = Int32(credentialIdText) ?? 0
        s.chainKey = chainKeyText
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        saveStatus = "✓ 已保存 (\(f.string(from: Date())))"
    }
}
