// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keyflow",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KeyflowCore", targets: ["KeyflowCore"]),
        .executable(name: "Keyflow", targets: ["Keyflow"]),
    ],
    targets: [
        // Business logic. No SwiftUI / AppKit imports allowed here.
        .target(name: "KeyflowCore"),
        // The macOS app.
        .executableTarget(name: "Keyflow", dependencies: ["KeyflowCore"]),
        .testTarget(name: "KeyflowCoreTests", dependencies: ["KeyflowCore"]),
        .testTarget(name: "KeyflowAppTests", dependencies: ["Keyflow", "KeyflowCore"]),
    ],
    swiftLanguageModes: [.v6]
)
