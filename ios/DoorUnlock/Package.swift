// swift-tools-version:5.5
import PackageDescription

// 只用来在 CI 里 `swift test` 协议层 (Crypto.swift)，不参与 App 构建 (App 由 XcodeGen 生成工程)。
let package = Package(
    name: "DoorCrypto",
    targets: [
        .target(name: "DoorCrypto", path: "Sources/DoorUnlock", sources: ["Crypto.swift", "UnlockFailure.swift"]),
        .testTarget(name: "CryptoTests", dependencies: ["DoorCrypto"], path: "Tests/CryptoTests"),
    ]
)
