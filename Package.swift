// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Summon",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .executable(name: "Summon", targets: ["Summon"]),
        .library(name: "SummonKit", targets: ["SummonKit"]),
        .library(name: "SummonUI", targets: ["SummonUI"]),
        // The phone and iPad views. A product because the iOS app target links it.
        .library(name: "SummonUIPhone", targets: ["SummonUIPhone"]),
        // The Mac app itself, for the Xcode target that archives it for the App Store.
        .library(name: "SummonMacApp", targets: ["SummonMacApp"]),
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

        // The touch half of the view layer, and the mirror image of SummonUIMac.
        //
        // A separate target rather than `#if os(iOS)` inside the shared views: the
        // Mac's list, sidebar and rows are built around hover, drag and a 32pt row,
        // and threading a second platform through them is how both ends rot. What is
        // genuinely shared — the design system, the model, the small components —
        // stays in SummonUI and is used by both.
        .target(name: "SummonUIPhone", dependencies: ["SummonUI", "SummonKit"]),

        // The Mac app: window/panel lifecycle and wiring. A library rather than an
        // executable, because an Xcode app target cannot link an executable — and the
        // App Store needs an archive that only Xcode produces.
        .target(
            name: "SummonMacApp",
            dependencies: ["SummonKit", "SummonUI", "SummonKitMac", "SummonUIMac"]),

        // The runtime harnesses: self-test, UI and drag probes, paste and path checks.
        // Linked only by the development launcher, never by the App Store build.
        .target(
            name: "SummonHarness",
            dependencies: ["SummonMacApp", "SummonKit", "SummonUI", "SummonKitMac", "SummonUIMac"]),

        // Development launcher: the app plus the harness. What build-app.sh packages.
        .executableTarget(
            name: "Summon",
            dependencies: ["SummonMacApp", "SummonHarness"]),

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
