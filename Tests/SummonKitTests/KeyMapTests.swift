import Foundation
import Testing
@testable import SummonKit

@Suite("Keyboard model")
struct KeyMapTests {

    private func resolve(_ chord: KeyChord,
                         context: PanelContext = .results,
                         queryIsEmpty: Bool = false,
                         selectionIsFolder: Bool = false) -> PanelCommand? {
        PanelKeyMap.command(for: chord, in: context,
                            queryIsEmpty: queryIsEmpty, selectionIsFolder: selectionIsFolder)
    }

    // MARK: The promise the panel used to draw and never keep

    @Test("⌘1–⌘9 select by position", arguments: Array(1...9))
    func commandDigits(_ digit: Int) {
        let chord = KeyChord(.character(Character("\(digit)")), .command)
        #expect(resolve(chord) == .activateIndex(digit - 1))
    }

    @Test("⌘0 is not a binding, because no row is numbered 0")
    func commandZero() {
        #expect(resolve(KeyChord(.character("0"), .command)) == nil)
    }

    // MARK: Activation

    @Test("Return and its modifiers pick the delivery")
    func activation() {
        #expect(resolve(KeyChord(.enter)) == .activate(.paste))
        #expect(resolve(KeyChord(.enter, .command)) == .activate(.copy))
        #expect(resolve(KeyChord(.enter, .option)) == .activate(.open))
        #expect(resolve(KeyChord(.enter, .shift)) == .activate(.plainPaste))
    }

    @Test("Command wins over the others, matching the order the panel checks them")
    func modifierPrecedence() {
        #expect(resolve(KeyChord(.enter, [.command, .shift])) == .activate(.copy))
    }

    // MARK: Movement

    @Test("Arrows, page keys and first/last")
    func movement() {
        #expect(resolve(KeyChord(.up)) == .move(-1))
        #expect(resolve(KeyChord(.down)) == .move(1))
        #expect(resolve(KeyChord(.pageUp)) == .move(-8))
        #expect(resolve(KeyChord(.pageDown)) == .move(8))
        #expect(resolve(KeyChord(.up, .command)) == .selectFirst)
        #expect(resolve(KeyChord(.down, .command)) == .selectLast)
        #expect(resolve(KeyChord(.home)) == .selectFirst)
        #expect(resolve(KeyChord(.end)) == .selectLast)
    }

    // MARK: Keys the panel must NOT claim
    //
    // Returning nil is what leaves ⌘C, ⌘V, ⌘A and ordinary typing working in the
    // search field. A key map that grabs everything breaks text editing.

    @Test("Editing shortcuts fall through to the field", arguments: ["c", "v", "a", "z", "x"])
    func editingShortcutsFallThrough(_ character: String) {
        #expect(resolve(KeyChord(.character(Character(character)), .command)) == nil)
    }

    @Test("Plain characters are typing, not commands")
    func plainCharactersFallThrough() {
        #expect(resolve(KeyChord(.character("k"))) == nil)
        #expect(resolve(KeyChord(.character("1"))) == nil)
    }

    // MARK: Context-sensitive keys

    @Test("Tab drills in only when the selection is a folder")
    func tabDrillsIn() {
        #expect(resolve(KeyChord(.tab), selectionIsFolder: true) == .drillIn)
        #expect(resolve(KeyChord(.tab), selectionIsFolder: false) == nil)
    }

    @Test("Backspace goes up a level only when the query is empty")
    func backspaceDrillsOut() {
        #expect(resolve(KeyChord(.delete), queryIsEmpty: true) == .drillOut)
        // With text typed it is an ordinary edit and must reach the field.
        #expect(resolve(KeyChord(.delete), queryIsEmpty: false) == nil)
    }

    @Test("Tab means next field while filling in, not drill-in")
    func tabInFillMode() {
        #expect(resolve(KeyChord(.tab), context: .fill, selectionIsFolder: true) == .nextField)
        #expect(resolve(KeyChord(.backTab), context: .fill) == .previousField)
        #expect(resolve(KeyChord(.tab, .shift), context: .fill) == .previousField)
    }

    // MARK: Escape unwinds one level, everywhere

    @Test("Escape resolves to escape in every context",
          arguments: [PanelContext.results, .actionMenu, .fill, .unlock])
    func escapeIsUniversal(_ context: PanelContext) {
        #expect(resolve(KeyChord(.escape), context: context) == .escape)
    }

    // MARK: The action menu

    @Test("⌘K toggles, so pressing it twice closes rather than reopening")
    func actionMenuToggles() {
        #expect(resolve(KeyChord(.character("k"), .command)) == .toggleActionMenu)
        #expect(resolve(KeyChord(.character("k"), .command), context: .actionMenu) == .toggleActionMenu)
    }

    @Test("Return runs the selected action, not the selected item")
    func actionMenuReturn() {
        #expect(resolve(KeyChord(.enter), context: .actionMenu) == .runSelectedAction)
        #expect(resolve(KeyChord(.up), context: .actionMenu) == .move(-1))
    }

    @Test("⌘1–⌘9 do not fire while the action menu is open")
    func digitsInactiveInActionMenu() {
        #expect(resolve(KeyChord(.character("3"), .command), context: .actionMenu) == nil)
    }

    // MARK: Direct action shortcuts

    @Test("Pin, reveal and delete have direct bindings")
    func directActions() {
        #expect(resolve(KeyChord(.character("p"), .command)) == .action(.togglePin))
        #expect(resolve(KeyChord(.character("r"), .command)) == .action(.reveal))
        #expect(resolve(KeyChord(.delete, .command)) == .action(.delete))
    }

    // MARK: The action list

    @Test("A locked item offers nothing that would reveal its contents")
    func lockedActions() {
        let actions = PanelKeyMap.actions(isBlobBacked: true, isLocked: true)
        #expect(!actions.contains(.paste))
        #expect(!actions.contains(.copy))
        #expect(!actions.contains(.open))
        #expect(!actions.contains(.reveal))
    }

    @Test("Open and Reveal appear only for something backed by a file")
    func blobActions() {
        #expect(PanelKeyMap.actions(isBlobBacked: true, isLocked: false).contains(.open))
        #expect(!PanelKeyMap.actions(isBlobBacked: false, isLocked: false).contains(.open))
        #expect(!PanelKeyMap.actions(isBlobBacked: false, isLocked: false).contains(.reveal))
    }

    @Test("Every action the menu lists has a title and a symbol")
    func actionsAreRenderable() {
        for action in PanelActionID.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.symbolName.isEmpty)
        }
        #expect(PanelActionID.delete.isDestructive)
    }

    // MARK: Hints come from the bindings themselves

    @Test("A hint string is derived from the chord, so it cannot drift")
    func hintsMatchBindings() {
        #expect(KeyChord(.enter).display == "↩")
        #expect(KeyChord(.enter, .command).display == "⌘↩")
        #expect(KeyChord(.enter, .shift).display == "⇧↩")
        #expect(KeyChord(.character("k"), .command).display == "⌘K")
        #expect(KeyChord(.delete, .command).display == "⌘⌫")
        #expect(KeyChord(.enter, [.command, .shift]).display == "⇧⌘↩")
    }

    @Test("Every action with a direct binding renders that binding")
    func actionChordsRender() {
        #expect(PanelKeyMap.chord(for: .copy)?.display == "⌘↩")
        #expect(PanelKeyMap.chord(for: .togglePin)?.display == "⌘P")
        #expect(PanelKeyMap.chord(for: .delete)?.display == "⌘⌫")
        // Actions that open a sheet deliberately have no one-key binding.
        #expect(PanelKeyMap.chord(for: .rename) == nil)
    }
}
