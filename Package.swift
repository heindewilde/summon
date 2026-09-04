// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Summon",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .executable(name: "Summon", targets: ["Summon"]),
        .library(name: "SummonKit", targets: ["SummonKit"]),
        .library(name: "SummonUI", targets: ["SummonUI"]),
    ],
    targets: [
        // Pure logic. No SwiftUI, no AppKit, no UIKit — and now the compiler agrees,
        // because the platform-bound half lives in SummonKitMac and this target has
        // to build for a phone as well.
        .target(name: "SummonKit"),

        // Carbon hot keys, insertion into another app, the Finder selection,
        // pasteboard watching. A Mac is load-bearing for all of it.
        .target(name: "SummonKitMac", dependencies: ["SummonKit"]),

        // Shared SwiftUI views + the design system.
        .target(name: "SummonUI", dependencies: ["SummonKit"]),

        // The panel, the menu bar, and the views that reach into AppKit.
        .target(name: "SummonUIMac", dependencies: ["SummonUI", "SummonKitMac"]),

        // Thin executable: window/panel lifecycle and wiring.
        .executableTarget(
            name: "Summon",
            dependencies: ["SummonKit", "SummonUI", "SummonKitMac", "SummonUIMac"]),

        .testTarget(name: "SummonKitTests", dependencies: ["SummonKit"]),

        // The macOS logic layer's own tests, for the same reason the target exists:
        // a test that needs NSPasteboard cannot live in a suite that has to compile
        // without it.
        .testTarget(name: "SummonKitMacTests", dependencies: ["SummonKitMac", "SummonKit"]),

        // The design system's own tests. This target exists so contrast can be
        // asserted against `Theme` itself: the assertions used to live in
        // SummonKitTests, which cannot import SummonUI, so they hand-copied every
        // alpha as a raw number — and a token could then change without failing
        // anything. Views still are not unit-tested; colour now is.
        .testTarget(name: "SummonUITests", dependencies: ["SummonUI"]),
    ]
)
