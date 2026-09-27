// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Daisy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DaisyCore", targets: ["DaisyCore"]),
        .executable(name: "Daisy", targets: ["Daisy"])
    ],
    targets: [
        .target(
            name: "DaisyCore",
            path: "macOS/DaisyCore"
        ),
        .executableTarget(
            name: "Daisy",
            dependencies: ["DaisyCore"],
            path: "macOS/DaisyApp",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/copilot-runtime"),
                .copy("Resources/litellm-requirements.txt"),
                .copy("Resources/litellm-runtime-version.txt")
            ]
        ),
        .testTarget(
            name: "DaisyCoreTests",
            dependencies: ["DaisyCore"],
            path: "Tests/macOS/DaisyCoreTests"
        )
    ]
)
