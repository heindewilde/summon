import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SummonKit
@testable import SummonKitMac

/// How a drag says which row it came from.
///
/// This suite exists because the first fix looked right and did nothing. The item's
/// identity was registered on the `NSItemProvider`, the type was declared in the
/// bundle, the drop delegate recognised the cargo — and the id still could not be
/// read back, because SwiftUI hands `performDrop` a provider with an empty
/// `registeredTypeIdentifiers` for a custom type. The bytes live on the pasteboard.
/// These lock down the route that actually carries them.
@Suite("Drag identity")
@MainActor
struct DragIdentityTests {

    private func board(_ name: String) -> NSPasteboard {
        let board = NSPasteboard(name: .init("summon.test.\(name)"))
        board.clearContents()
        return board
    }

    @Test("The drag types are declared by the bundle, not invented at runtime")
    func typesAreDeclared() {
        // A dynamic type is what you get when the identifier is not declared in
        // Info.plist. The drop side would then fail to match it, and the whole
        // mechanism would go quiet rather than break loudly.
        #expect(SummonDragType.item.identifier == "com.heindewilde.summon.item")
        #expect(SummonDragType.folder.identifier == "com.heindewilde.summon.folder")
        #expect(!SummonDragType.item.isDynamic)
        #expect(!SummonDragType.folder.isDynamic)
    }

    @Test("An item id survives a trip through the pasteboard")
    func itemRoundTrip() {
        let board = board("item")
        let id = UUID()
        SummonDragType.write(id, of: SummonDragType.item, to: board)
        #expect(SummonDragType.read(SummonDragType.item, from: board) == id)
        board.releaseGlobally()
    }

    @Test("An item drag is not mistaken for a folder drag")
    func typesDoNotCollide() {
        let board = board("collide")
        let id = UUID()
        SummonDragType.write(id, of: SummonDragType.item, to: board)
        // Both conform to public.data; nothing else may make them interchangeable,
        // or dropping an item on a folder would try to reparent a folder that does
        // not exist.
        #expect(SummonDragType.read(SummonDragType.folder, from: board) == nil)
        board.releaseGlobally()
    }

    @Test("A pasteboard with no Summon identity reads as nothing")
    func foreignDragCarriesNoIdentity() {
        let board = board("foreign")
        board.setString("some text from another app", forType: .string)
        #expect(SummonDragType.read(SummonDragType.item, from: board) == nil)
        #expect(SummonDragType.read(SummonDragType.folder, from: board) == nil)
        board.releaseGlobally()
    }

    @Test("A garbled identity is refused rather than guessed at")
    func garbageIsRefused() {
        let board = board("garbage")
        board.setData(Data("not-a-uuid".utf8),
                      forType: .init(SummonDragType.item.identifier))
        #expect(SummonDragType.read(SummonDragType.item, from: board) == nil)
        board.releaseGlobally()
    }

    @Test("A provider carries the identity alongside its contents")
    func providerCarriesBoth() async {
        // The provider still has to advertise the type: that is what the drop side
        // matches on to decide it is holding one of our rows at all.
        let id = UUID()
        let payload = InsertPayload(plainText: "Some snippet body")
        guard let provider = DragProvider.make(for: payload, title: "Snippet", itemID: id) else {
            Issue.record("no provider")
            return
        }
        #expect(provider.registeredTypeIdentifiers.contains(SummonDragType.item.identifier))
        // And the content an external drop needs is still there.
        #expect(provider.registeredTypeIdentifiers.contains { $0.contains("text") })
    }

    @Test("A provider built without an id carries no identity")
    func providerWithoutID() {
        let payload = InsertPayload(plainText: "Some snippet body")
        let provider = DragProvider.make(for: payload, title: "Snippet")
        #expect(provider?.registeredTypeIdentifiers.contains(SummonDragType.item.identifier) == false)
    }
}
