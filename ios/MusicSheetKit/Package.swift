// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MusicSheetKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MusicSheetKit", targets: ["MusicSheetKit"]),
    ],
    targets: [
        .target(name: "MusicSheetKit"),
        .testTarget(name: "MusicSheetKitTests", dependencies: ["MusicSheetKit"]),
    ]
)
