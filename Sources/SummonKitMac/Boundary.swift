/// The macOS half of the logic layer.
///
/// `SummonKit` claims to be pure logic that any platform can run. It said so in the
/// package manifest and in the README while twelve of its thirty-two files imported
/// AppKit, because nothing made the claim false in a way the compiler noticed —
/// there is only one platform to build for, so an unconditional `import AppKit`
/// compiles perfectly well inside a target documented as having none.
///
/// This target is the enforcement. Everything here needs a Mac to mean anything:
/// Carbon hot keys, pasting into another app's text field, reading the Finder
/// selection, watching `NSPasteboard`. None of it has an iOS equivalent worth
/// pretending to — an iPhone has no frontmost app to paste into and no global
/// shortcut to register — so this is a boundary rather than a porting queue.
///
/// The rule for deciding where something goes: if it would still make sense on a
/// phone, it belongs in `SummonKit`, whatever it currently imports.
public enum SummonKitMac {}
