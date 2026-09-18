// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexAccounts",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexAccounts", targets: ["CodexAccounts"]),
        .executable(name: "account-check", targets: ["AccountCheck"])
    ],
    targets: [
        .target(name: "AccountCore", resources: [.process("Resources")]),
        .executableTarget(name: "CodexAccounts", dependencies: ["AccountCore"]),
        .executableTarget(name: "AccountCheck", dependencies: ["AccountCore"])
    ]
)
