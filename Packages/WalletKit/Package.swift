// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WalletKit",
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(name: "WalletDomain", targets: ["WalletDomain"]),
        .library(name: "WalletData", targets: ["WalletData"]),
        .library(name: "WalletFeature", targets: ["WalletFeature"]),
    ],
    targets: [
        .target(name: "WalletDomain"),
        .target(name: "WalletData", dependencies: ["WalletDomain"]),
        .target(name: "WalletFeature", dependencies: ["WalletDomain"]),
        .testTarget(name: "WalletKitTests", dependencies: ["WalletDomain", "WalletData", "WalletFeature"]),
    ]
)
