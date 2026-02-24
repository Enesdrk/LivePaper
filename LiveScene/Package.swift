// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LiveScene",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LiveSceneCore", targets: ["LiveSceneCore"]),
        .library(name: "LiveSceneSaver", type: .dynamic, targets: ["LiveSceneSaver"]),
        .executable(name: "LiveSceneApp", targets: ["LiveSceneApp"]),
        .executable(name: "LiveSceneWorker", targets: ["LiveSceneWorker"])
    ],
    targets: [
        .target(name: "LiveSceneCore"),
        .target(
            name: "LiveSceneSaver",
            dependencies: ["LiveSceneCore"],
            linkerSettings: [
                .linkedFramework("ScreenSaver"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit")
            ]
        ),
        .executableTarget(name: "LiveSceneApp", dependencies: ["LiveSceneCore"]),
        .executableTarget(name: "LiveSceneWorker", dependencies: ["LiveSceneCore"]),
        .testTarget(name: "LiveSceneCoreTests", dependencies: ["LiveSceneCore"])
    ]
)
