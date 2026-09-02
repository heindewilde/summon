// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Summon",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Summon", targets: ["Summon"]),
        .library(name: "SummonKit", targets: ["SummonKit"]),
        .library(name: "SummonUI", targets: ["SummonUI"]),
    ],
    targets: [
        // Pure logic. No SwiftUI, no AppKit views. This is the entire test surface.
        .target(name: "SummonKit"),

        // Shared SwiftUI views + the design system.
        .target(name: "SummonUI", dependencies: ["SummonKit"]),

        // Thin executable: window/panel lifecycle and wiring.
        .executableTarget(name: "Summon", dependencies: ["SummonKit", "SummonUI"]),

        .testTarget(name: "SummonKitTests", dependencies: ["SummonKit"]),
    ]
)
