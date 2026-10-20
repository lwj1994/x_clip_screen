// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "XClipPermissionBridge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "XClipPermissionBridge", type: .dynamic, targets: ["XClipPermissionBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.3")
    ],
    targets: [
        .target(
            name: "XClipPermissionBridge",
            dependencies: [.product(name: "PermissionFlow", package: "PermissionFlow")],
            path: "Sources/PermissionBridge"
        )
    ]
)
