import CoreGraphics

/// Where a drag would land relative to the row under the pointer.
public enum FolderDropZone: Equatable, Sendable {
    case before
    case into
    case after
}

/// Turns a pointer position inside a row into an intent.
///
/// Pure geometry, kept out of the view layer so it can be tested: the flickering
/// indicator was a bug in exactly this arithmetic, and it is not something you can
/// catch by looking at a screenshot.
public enum DropZoneResolver {

    /// How much extra room the zone already showing keeps for itself.
    ///
    /// This is the whole fix for the jumping line. A 26pt row split into three flat
    /// bands puts the boundaries about 8pt apart, so an ordinary unsteady hand
    /// crosses them several times a second and the indicator flips between "beside"
    /// and "inside" faster than you can read it. Widening whichever zone is currently
    /// showing means leaving it takes a deliberate movement rather than a tremor.
    public static let hysteresis: CGFloat = 3.5

    /// - Parameters:
    ///   - y: pointer position within the row, from its top edge.
    ///   - height: the row's height.
    ///   - canReorder: whether "beside" is a meaningful outcome. Only a folder has a
    ///     position among siblings; an item or a file has one meaning — put it in
    ///     this folder — and offering three targets for one outcome is why dropping
    ///     onto a folder felt like a lottery.
    ///   - current: the zone already on screen for this row, if any.
    public static func zone(y: CGFloat, height: CGFloat, canReorder: Bool,
                            current: FolderDropZone?) -> FolderDropZone {
        guard canReorder else { return .into }

        // A proportional edge with a floor: at 26pt a third of the row is 8.6pt, which
        // is a reasonable target, but the floor keeps it usable if rows ever shrink.
        let edge = max(6, height * 0.3)
        let top = edge + (current == .before ? hysteresis : -hysteresis)
        let bottom = height - edge - (current == .after ? hysteresis : -hysteresis)
        if y < top { return .before }
        if y > bottom { return .after }
        return .into
    }

    /// The same decision for a row that can only be split in two: above the midpoint
    /// means before, below means after.
    public static func placeAfter(y: CGFloat, height: CGFloat, current: Bool?) -> Bool {
        let midpoint = height / 2 + (current == true ? -hysteresis : hysteresis)
        return y > midpoint
    }
}
