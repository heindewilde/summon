import SwiftUI

private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True while rendering to an image for design review. AppKit-backed views
    /// substitute a static SwiftUI equivalent, because `ImageRenderer` cannot draw
    /// an `NSViewRepresentable`.
    var isSnapshotting: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// A `ScrollView` in normal use; a plain stack while snapshotting.
///
/// `ImageRenderer` proposes an unbounded height to a `ScrollView`, which collapses
/// its content to nothing. Swapping the container is the only way to review scrolling
/// surfaces as images. Behaviour in the shipped app is unchanged.
public struct SnapshotSafeScrollView<Content: View>: View {
    @Environment(\.isSnapshotting) private var isSnapshotting
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if isSnapshotting {
            VStack(spacing: 0) {
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        } else {
            ScrollView { content }
        }
    }
}
