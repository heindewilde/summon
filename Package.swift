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
        // Pure logic. No SwiftUI, no AppKit views.
        .target(name: "SummonKit"),

        // Shared SwiftUI views + the design system.
        .target(name: "SummonUI", dependencies: ["SummonKit"]),

        // Thin executable: window/panel lifecycle and wiring.
        .executableTarget(name: "Summon", dependencies: ["SummonKit", "SummonUI"]),

        .testTarget(name: "SummonKitTests", dependencies: ["SummonKit"]),

        // The design system's own tests. This target exists so contrast can be
        // asserted against `Theme` itself: the assertions used to live in
        // SummonKitTests, which cannot import SummonUI, so they hand-copied every
        // alpha as a raw number — and a token could then change without failing
        // anything. Views still are not unit-tested; colour now is.
        .testTarget(name: "SummonUITests", dependencies: ["SummonUI"]),
    ]
)
