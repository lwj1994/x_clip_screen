// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "XScreenCapture",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "XScreenCapture", targets: ["XScreenCapture"]),
        .library(name: "XClipPermissionBridge", type: .dynamic, targets: ["XClipPermissionBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.3"),
        .package(url: "https://github.com/lwj1994/apple_view_model.git", exact: "0.13.0")
    ],
    targets: [
        // 对 QQ 截图框架私有 ABI 的加载与 runtime hook，保留 Objective-C。
        .target(
            name: "XClipEngine",
            path: "Sources/XClipEngine",
            linkerSettings: [.linkedFramework("Cocoa")]
        ),
        // AppKit 宿主：菜单、设置、快捷键、截图会话和更新，由 AppleViewModel 管理状态与依赖。
        .executableTarget(
            name: "XScreenCapture",
            dependencies: [
                "XClipEngine",
                .product(name: "AppleViewModel", package: "apple_view_model")
            ],
            path: "Sources/XScreenCapture",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers"),
                // 提取的 QQ framework 之间以 @rpath 互相引用。
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .target(
            name: "XClipPermissionBridge",
            dependencies: [.product(name: "PermissionFlow", package: "PermissionFlow")],
            path: "Sources/PermissionBridge"
        ),
        .testTarget(
            name: "XScreenCaptureTests",
            dependencies: ["XScreenCapture"],
            path: "Tests/XScreenCaptureTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
