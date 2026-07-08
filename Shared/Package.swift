// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FitTrackShared",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "FitTrackShared", targets: ["FitTrackShared"])
    ],
    targets: [
        .target(name: "FitTrackShared")
    ]
)
