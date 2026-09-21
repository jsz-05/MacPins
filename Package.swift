// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPins",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacPins",
            path: "Sources/MacPins",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("IOSurface"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        )
    ]
)
