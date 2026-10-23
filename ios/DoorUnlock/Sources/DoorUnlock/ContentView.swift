import SwiftUI

struct ContentView: View {
    @StateObject private var ble = DoorBLEManager()
    @AppStorage("agreed_disclaimer") private var agreedDisclaimer = false

    @State private var deviceIdText = ""
    @State private var projectIdText = ""
    @State private var credentialIdText = ""
    @State private var chainKeyText = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var fetchStatus = ""
    @State private var isFetching = false

    var body: some View {
        if !agreedDisclaimer {
            disclaimerView
        } else {
            mainView
        }
    }

    private var disclaimerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("免责声明").font(.title2).bold()
            Text("""
            本应用为个人学习与自用目的、基于公开信息对"住理生活"门锁通讯协议的逆向移植，\
            仅用于使用你自己账号换取的凭证开启你自己绑定的门锁。

            不提供、不包含任何绕过他人账号鉴权或批量开锁的功能。\
            使用本应用产生的一切后果由使用者自行承担。
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            Button("我已阅读并同意") { agreedDisclaimer = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var mainView: some View {
        NavigationStack {
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

                Section("门锁参数 (登录拉取后自动填入，可手动修改)") {
                    TextField("设备ID (deviceId)", text: $deviceIdText).keyboardType(.numberPad)
                    TextField("项目ID (projectId)", text: $projectIdText).keyboardType(.numberPad)
                    TextField("凭证ID (credentialId)", text: $credentialIdText).keyboardType(.numberPad)
                    TextField("chainKey (64位hex)", text: $chainKeyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存参数") { saveSettings() }
                }

                Section("开门") {
                    HStack {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 10, height: 10)
                        Text(ble.statusText)
                    }
                    Button(ble.state == .scanning || ble.state == .connecting || ble.state == .unlocking ? "开门中..." : "开门") {
                        Task { await ble.unlock() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ble.state == .scanning || ble.state == .connecting || ble.state == .unlocking)
                }

                Section("通讯日志") {
                    ForEach(ble.log.suffix(50), id: \.self) { line in
                        Text(line).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            .navigationTitle("门锁 (自用版)")
            .onAppear(perform: loadSettings)
        }
    }

    private var stateColor: Color {
        switch ble.state {
        case .success: return .green
        case .failed: return .red
        case .idle: return .gray
        default: return .orange
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
            s.credentialId = addr.credentialId
            s.chainKey = addr.chainKey
            loadSettings()
            fetchStatus = "✓ 已获取: \(addr.buildingName)\(addr.floorName)\(addr.roomName) (device=\(addr.deviceId))"
        } catch {
            fetchStatus = "拉取失败: \(error.localizedDescription)"
        }
        isFetching = false
    }
}

#Preview {
    ContentView()
}
