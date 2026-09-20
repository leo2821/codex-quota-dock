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
    dependencies: [
        .package(url: "https://github.com/auth0/JWTDecode.swift.git", exact: "4.0.0")
    ],
    targets: [
        .target(name: "AccountCore", dependencies: [.product(name: "JWTDecode", package: "JWTDecode.swift")],
                resources: [.process("Resources")]),
        .executableTarget(name: "CodexAccounts", dependencies: ["AccountCore"]),
        .executableTarget(name: "AccountCheck", dependencies: ["AccountCore"])
    ]
)
