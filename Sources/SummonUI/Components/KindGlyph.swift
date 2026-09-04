import AppKit
import SwiftUI
import SummonKit

/// The bare type glyph, i.e. `KindIcon(style: .bare)`.
///
/// Its old comment said there was no tile because "in a monochrome list the symbol is
/// the only coloured element" — reasoning that assumed a neutral selection. The list is
/// not monochrome any more, and the conclusion survives for a better reason: the glyph
/// now sits *on* the accent when its row is chosen, so a second filled shape would put
/// three layers of violet in one 20pt square.
public struct KindGlyph: View {
    public let kind: ItemKind
    public var isLocked = false
    public var size: CGFloat = 15

    public init(kind: ItemKind, isLocked: Bool = false, size: CGFloat = 15) {
        self.kind = kind
        self.isLocked = isLocked
        self.size = size
    }

    public var body: some View {
        KindIcon(kind: kind, style: .bare, size: size, isLocked: isLocked)
    }
}
