// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LivePaper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LivePaperCore", targets: ["LivePaperCore"]),
        .library(name: "LivePaperSaver", type: .dynamic, targets: ["LivePaperSaver"]),
        .executable(name: "LivePaperApp", targets: ["LivePaperApp"]),
        .executable(name: "LivePaperWorker", targets: ["LivePaperWorker"])
    ],
    targets: [
        .target(name: "LivePaperCore"),
        .target(
            name: "LivePaperSaver",
            dependencies: ["LivePaperCore"],
            linkerSettings: [
                .linkedFramework("ScreenSaver"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit")
            ]
        ),
        .executableTarget(name: "LivePaperApp", dependencies: ["LivePaperCore"]),
        .executableTarget(name: "LivePaperWorker", dependencies: ["LivePaperCore"]),
        .testTarget(name: "LivePaperCoreTests", dependencies: ["LivePaperCore"])
    ]
)
