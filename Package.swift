// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftReadability",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "SwiftReadability",
            targets: ["SwiftReadability"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.11.3"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "SwiftReadability",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            path: "SwiftReadability"
        ),
        .testTarget(
            name: "SwiftReadabilityTests",
            dependencies: ["SwiftReadability"],
            path: "SwiftReadabilityTests",
            resources: [
                .process("html_examples")
            ]
        )
    ]
)
