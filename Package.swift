// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeadlessHelper",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HeadlessHelper",
            path: "Sources/HeadlessHelper",
            exclude: ["Info.plist", "Utilities/click_helper.swift"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
