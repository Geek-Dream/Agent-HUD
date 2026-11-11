// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AgentHUD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentHUD", targets: ["AgentHUD"])
    ],
    targets: [
        .executableTarget(
            name: "AgentHUD",
            path: "Sources/AgentHUD"
        )
    ]
)
