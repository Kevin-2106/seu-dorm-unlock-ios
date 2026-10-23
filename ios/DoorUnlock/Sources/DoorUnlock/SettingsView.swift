import SwiftUI
import PhotosUI

/// 设置页：账号登录、门锁参数、配置码导入导出、各种调试日志。
/// 首页只留开门按钮，细节都在这。
struct SettingsView: View {
    @ObservedObject var ble: DoorBLEManager
    @ObservedObject var nfc: DoorNFCManager
    @ObservedObject private var background = BackgroundImageStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var deviceIdText: String
    @State private var projectIdText: String
    @State private var credentialIdText: String
    @State private var chainKeyText: String
    @State private var phone: String
    @State private var password = ""
    @State private var fetchStatus = ""
    @State private var isFetching = false
    @State private var configStatus = ""
    @State private var saveStatus = ""

    /// 自定义 init：把当前已保存的参数在视图"创建"的这一刻就灌进 @State，
    /// 而不是等 .onAppear 之后才赋值。之前只靠 onAppear 时，Form 里的 TextField
    /// 在首次渲染那一帧用的还是空字符串，SwiftUI 的 List/Form 对已渲染过的行
    /// 有时不会因为后续 state 更新就主动重绘，表现为"要点一下输入框才会显示出来"。
    init(ble: DoorBLEManager, nfc: DoorNFCManager) {
        self.ble = ble
        self.nfc = nfc
        let s = SettingsManager.shared
        _deviceIdText = State(initialValue: s.deviceId == 0 ? "" : String(s.deviceId))
        _projectIdText = State(initialValue: s.projectId == 0 ? "" : String(s.projectId))
        _credentialIdText = State(initialValue: s.credentialId == 0 ? "" : String(s.credentialId))
        _chainKeyText = State(initialValue: s.chainKey)
        _phone = State(initialValue: s.loginPhone)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    // LabeledContent 是 iOS 16+，主 app 还要兼容 iOS 15，用 HStack
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(BuildInfo.summary).foregroundStyle(.secondary).monospacedDigit()
                    }
                    HStack {
                        Text("小组件扩展")
                        Spacer()
                        Text(BuildInfo.widgetExtensionInstalled ? "已安装" : "未安装").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                } footer: {
                    if !BuildInfo.widgetExtensionInstalled {
                        Text("未安装 = 侧载时被移除了 (免费 Apple ID 只有 10 个 App ID 额度，扩展要多占 1 个)。\n没有扩展也能用: 在\"快捷指令\"里添加\"开门\"动作，放到锁屏快捷指令控制 / Action 按钮 / 轻点背面 / Siri。")
                    }
                }

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

                Section("首页外观") {
                    NavigationLink("视觉与震动调节") { TuningView() }
                    if #available(iOS 16.0, *) {
                        BackgroundPickerRow()
                    } else {
                        Text("自定义背景需要 iOS 16 及以上").font(.caption).foregroundStyle(.secondary)
                    }
                    if background.image != nil {
                        Button("恢复默认背景", role: .destructive) { background.clear() }
                    }
                }

                Section("门锁参数 (登录拉取/导入配置码后自动填入，可手动修改)") {
                    TextField("设备ID (deviceId)", text: $deviceIdText).keyboardType(.numberPad)
                    TextField("项目ID (projectId)", text: $projectIdText).keyboardType(.numberPad)
                    TextField("凭证ID (credentialId)", text: $credentialIdText).keyboardType(.numberPad)
                    TextField("chainKey (64位hex)", text: $chainKeyText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存参数") { saveSettings() }
                    if !saveStatus.isEmpty {
                        Text(saveStatus).font(.footnote).foregroundStyle(.green)
                    }
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
        saveStatus = "✓ 已保存 (\(formattedNow()))"
    }

    private func formattedNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
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

/// PhotosPickerItem 这个类型本身标了 @available(iOS 16, *)，哪怕只是当一个
/// @State 属性的类型声明，也会在 iOS15 部署目标下报 "only available in iOS 16"。
/// 拆成单独一个同样打了 @available 的子 View，SettingsView 那边只在
/// `if #available(iOS 16, *)` 分支里构造它，这样 iOS16 以下的类型检查完全碰不到它。
@available(iOS 16.0, *)
private struct BackgroundPickerRow: View {
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickedItem, matching: .images) {
            Label("选择背景图片", systemImage: "photo")
        }
        .onChange(of: pickedItem) { newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { return }
                BackgroundImageStore.shared.save(uiImage)
            }
        }
    }
}
