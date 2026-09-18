// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexAccounts",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexAccounts", targets: ["CodexAccounts"]),
        .executable(name: "account-check", targets: ["AccountCheck"])
    ],
    targets: [
        .target(name: "AccountCore"),
        .executableTarget(name: "CodexAccounts", dependencies: ["AccountCore"]),
        .executableTarget(name: "AccountCheck", dependencies: ["AccountCore"])
    ]
)
