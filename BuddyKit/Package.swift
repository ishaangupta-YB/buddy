// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BuddyKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "BuddyKit",
            targets: ["BuddyKit"]
        )
    ],
    targets: [
        .target(
            name: "BuddyKit"
        ),
        .testTarget(
            name: "BuddyKitTests",
            dependencies: ["BuddyKit"]
        )
    ]
)
