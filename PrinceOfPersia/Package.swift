// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrinceOfPersia",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Prince", targets: ["Prince"])
    ],
    targets: [
        // LAW 5: PoPCore declares ZERO dependencies and imports no SpriteKit,
        // AppKit, GameplayKit or AVFoundation. The faithful port lives here.
        .target(name: "PoPCore"),

        // The Swift 6 rewrite of the host: rendering, input, audio, flow.
        .target(
            name: "PoPHost",
            dependencies: ["PoPCore"],
            resources: [.copy("Resources")]
        ),

        .executableTarget(name: "Prince", dependencies: ["PoPHost"]),

        .testTarget(name: "PoPCoreTests", dependencies: ["PoPCore"]),
    ],
    swiftLanguageModes: [.v6]
);
