// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "macinputsourcelock",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "MacInputSourceLock",
            targets: ["MacInputSourceLock"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "MacInputSourceLock",
            path: "Sources/MacInputSourceLock",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
