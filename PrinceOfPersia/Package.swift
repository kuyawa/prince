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
        //
        // The game assets ship in THIS target's bundle, not PoPHost's, so the data
        // layer can be exercised headlessly by PoPCoreTests through the same code
        // path the game uses.
        .target(
            name: "PoPCore",
            resources: [.copy("Resources")]
        ),

        // The Swift 6 rewrite of the host: rendering, input, audio, flow.
        .target(name: "PoPHost", dependencies: ["PoPCore"]),

        .executableTarget(name: "Prince", dependencies: ["PoPHost"]),

        .testTarget(name: "PoPCoreTests", dependencies: ["PoPCore"]),
    ],
    swiftLanguageModes: [.v6]
);
