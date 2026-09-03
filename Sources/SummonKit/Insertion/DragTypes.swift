import AppKit
import Foundation
import UniformTypeIdentifiers

/// The types Summon uses to recognise its own drags.
///
/// A row's provider vends its *content* — a file, RTF, plain text — because that is
/// what another app needs when you drag out of Summon. But content carries no
/// identity, so a drop back onto our own sidebar had nothing to file: an item
/// dragged onto a folder arrived looking like a stray file URL and was re-imported
/// as a duplicate, or like plain text and was dropped on the floor. These identifier
/// types ride along with the content, so an internal drop knows exactly which row it
/// is holding while an external drop still gets real content.
public enum SummonDragType {
    public static let item = UTType(exportedAs: "com.heindewilde.summon.item",
                                    conformingTo: .data)
    public static let folder = UTType(exportedAs: "com.heindewilde.summon.folder",
                                      conformingTo: .data)

    /// Both, for a drop target that accepts either.
    public static let all: [UTType] = [item, folder]
}

public extension SummonDragType {
    /// Writes a row's identity onto a pasteboard, and reads it back.
    ///
    /// The drag pasteboard is the route that actually works for an in-app drop.
    /// SwiftUI hands `performDrop` an `NSItemProvider` whose
    /// `registeredTypeIdentifiers` is *empty* for a custom type: it knows the drag
    /// conforms — that is how the drop is recognised at all — but will not vend the
    /// representation back, so decoding the id off the provider returns nothing. The
    /// bytes are on the pasteboard underneath it the whole time.
    static func write(_ id: UUID, of type: UTType, to board: NSPasteboard) {
        board.setData(Data(id.uuidString.utf8),
                      forType: NSPasteboard.PasteboardType(type.identifier))
    }

    static func read(_ type: UTType, from board: NSPasteboard) -> UUID? {
        guard let data = board.data(forType: NSPasteboard.PasteboardType(type.identifier))
        else { return nil }
        return UUID(uuidString: String(decoding: data, as: UTF8.self))
    }
}

public extension NSItemProvider {
    /// Tags a provider with the row it came from, without disturbing the content
    /// representations an external drop relies on.
    func registerSummonID(_ id: UUID, as type: UTType) {
        let data = Data(id.uuidString.utf8)
        registerDataRepresentation(for: type) { completion in
            completion(data, nil)
            return nil
        }
    }
}
