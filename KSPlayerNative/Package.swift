// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KSPlayer",
    platforms: [.tvOS(.v17)],
    products: [.library(name: "KSPlayer", targets: ["KSPlayer"])],
    targets: [.target(name: "KSPlayer")]
)
