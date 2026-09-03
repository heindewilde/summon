import CoreGraphics
import Testing
@testable import SummonKit

/// The arithmetic behind the drop indicator.
///
/// Worth a suite of its own because the symptom — "the grey line jumps around" — is
/// invisible in a screenshot and impossible to reproduce by hand on demand. It is a
/// boundary problem in twenty lines of geometry, so it gets tested like one.
@Suite("Drop zones")
struct DropZoneTests {

    private let height: CGFloat = 26

    private func zone(_ y: CGFloat, current: FolderDropZone? = nil) -> FolderDropZone {
        DropZoneResolver.zone(y: y, height: height, canReorder: true, current: current)
    }

    @Test("The top and bottom edges mean beside, the middle means inside")
    func threeBands() {
        #expect(zone(1) == .before)
        #expect(zone(13) == .into)
        #expect(zone(25) == .after)
    }

    @Test("Anything that cannot be reordered only ever lands inside")
    func itemsAlwaysLandInside() {
        // An item or a file has one meaning — put it in this folder. Offering
        // "before" and "after" as well was three targets for one outcome, and picking
        // the wrong one silently did nothing at all.
        for y in stride(from: CGFloat(0), through: height, by: 1) {
            #expect(DropZoneResolver.zone(y: y, height: height,
                                          canReorder: false, current: nil) == .into)
        }
    }

    @Test("The zone already showing is harder to leave than to enter")
    func hysteresis() {
        // One point either side of the plain boundary at 7.8pt. With no hysteresis
        // both of these resolve differently and a hand that is merely unsteady flips
        // the indicator back and forth several times a second.
        let boundary = height * 0.3

        // Showing "before": the band is widened, so a point just past the boundary
        // still reads as before.
        #expect(zone(boundary + 2, current: .before) == .before)
        // Showing "into": the same point reads as into, so it does not flip.
        #expect(zone(boundary + 2, current: .into) == .into)
        // A deliberate move well clear of the boundary switches either way.
        #expect(zone(boundary + 6, current: .before) == .into)
        #expect(zone(1, current: .into) == .before)
    }

    @Test("A pointer creeping across the boundary changes its mind once, not repeatedly")
    func noFlicker() {
        // Walks the pointer down the row a third of a point at a time, feeding each
        // answer back in as the current zone — which is exactly what a real drag
        // does. Three bands mean at most two changes; anything more is the flicker.
        var current: FolderDropZone?
        var changes = 0
        for step in 0...(Int(height) * 3) {
            let next = zone(CGFloat(step) / 3, current: current)
            if next != current, current != nil { changes += 1 }
            current = next
        }
        #expect(changes == 2)
    }

    @Test("A two-way row splits at its midpoint, with the same steadiness")
    func placeAfter() {
        #expect(DropZoneResolver.placeAfter(y: 5, height: 40, current: nil) == false)
        #expect(DropZoneResolver.placeAfter(y: 35, height: 40, current: nil) == true)
        // Just past the midpoint, whichever way the line is already pointing wins.
        #expect(DropZoneResolver.placeAfter(y: 22, height: 40, current: true) == true)
        #expect(DropZoneResolver.placeAfter(y: 22, height: 40, current: false) == false)
    }
}
