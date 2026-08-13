// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentAwake",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "AgentAwake", targets: ["AgentAwake"]),
        .library(name: "AgentAwakeCore", targets: ["AgentAwakeCore"]),
    ],
    targets: [
        .target(name: "AgentAwakeCore"),
        .executableTarget(
            name: "AgentAwake",
            dependencies: ["AgentAwakeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "AgentAwakeCoreTests",
            dependencies: ["AgentAwakeCore"]
        ),
    ]
)
