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

/// A `LazyVStack` in normal use; an eager `VStack` while snapshotting.
///
/// Lazy stacks only realise the rows the scroll view has asked for, which is the
/// point — a 60-row result list should not build 60 rows to show 9. But
/// `ImageRenderer` never scrolls, so a lazy stack renders empty. Behaviour in the
/// shipped app is unchanged.
public struct SnapshotSafeLazyVStack<Content: View>: View {
    @Environment(\.isSnapshotting) private var isSnapshotting
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(alignment: HorizontalAlignment = .center,
                spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if isSnapshotting {
            VStack(alignment: alignment, spacing: spacing) { content }
        } else {
            LazyVStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}
