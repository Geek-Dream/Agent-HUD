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
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.29.0")
    ],
    targets: [
        .executableTarget(
            name: "AgentHUD",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOSSL", package: "swift-nio-ssl")
            ],
            path: "Sources/AgentHUD"
        )
    ]
)
