// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "macstaticlanguage",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "MacStaticLanguage",
            targets: ["MacStaticLanguage"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "MacStaticLanguage",
            path: "Sources/MacStaticLanguage"
        ),
    ]
)
