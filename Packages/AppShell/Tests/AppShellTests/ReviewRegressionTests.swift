import CoreGraphics
import Testing
@testable import AppShell

/// Regression tests for bugs found in the Phase 3 code review (2026-11-14).
@Suite struct Phase3ReviewTests {
    // V1: a drag held still before the release left the drag "open", so a later system move
    // (a display unplugged) was saved as the user's spot, and replugging no longer brought the
    // note back.

    // (#expect can't call mutating methods, so each step's result is read first.)

    @Test func aDragHeldStillBeforeReleaseIsSavedOnceThenClosed() {
        var drag = DragSaveTracker()
        let dragged = drag.moved(buttonDown: true)
        let heldStill = drag.settled(buttonDown: true)
        let released = drag.settled(buttonDown: false)
        #expect(dragged)
        #expect(heldStill == .waitForRelease) // no save while the button is held
        #expect(released == .save)            // saved once, on release
        #expect(!drag.isDragging)

        let systemMove = drag.moved(buttonDown: false) // e.g. a display unplugged later
        let afterSystemMove = drag.settled(buttonDown: false)
        #expect(!systemMove)
        #expect(afterSystemMove == .nothing)
    }

    @Test func theLastMoveAfterTheReleaseIsStillPartOfTheDrag() {
        var drag = DragSaveTracker()
        let dragged = drag.moved(buttonDown: true)
        let lateMove = drag.moved(buttonDown: false) // arrives after the release
        let settled = drag.settled(buttonDown: false)
        #expect(dragged && lateMove)
        #expect(settled == .save)
    }

    @Test func systemMovesAreNeverSaved() {
        var drag = DragSaveTracker()
        let moved = drag.moved(buttonDown: false)
        let settled = drag.settled(buttonDown: false)
        let finished = drag.finish()
        #expect(!moved)
        #expect(settled == .nothing)
        #expect(!finished)
    }

    @Test func expandingMidDragSavesTheDragAndClosesIt() {
        var drag = DragSaveTracker()
        _ = drag.moved(buttonDown: true)
        let shouldSave = drag.finish()
        #expect(shouldSave)
        #expect(!drag.isDragging)
    }

    // V2: a height change re-anchored to the current nearest corner while placement used the
    // saved corner, so a note grown past the screen's middle and shrunk back drifted, then
    // jumped back on the next collapse or display change. (Reproduced on 1440×875.)

    private let display = Display(id: "MAIN", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))

    private func heightChange(to height: CGFloat, from current: CGRect, positions: NotePositions,
                              isDragging: Bool = false) -> CGRect? {
        NoteGeometry.collapsedFrame(
            afterHeightChangeTo: CGSize(width: 300, height: height), current: current, currentDisplay: display,
            positions: positions, displays: [display], isDragging: isDragging)
    }

    @Test func growingThenShrinkingReturnsTheNoteExactly() throws {
        var positions = NotePositions()
        let dragged = CGRect(x: 100, y: 450, width: 300, height: 100) // top half → anchored top-left
        positions.save(frame: dragged, on: display)

        let grown = try #require(heightChange(to: 400, from: dragged, positions: positions))
        #expect(grown.maxY == dragged.maxY) // grows downwards from the saved top corner
        let shrunk = try #require(heightChange(to: 100, from: grown, positions: positions))
        #expect(shrunk == dragged)
        // And it's exactly where a later re-place (collapse, display change) puts it: no jump.
        #expect(positions.frame(size: shrunk.size, displays: [display]) == shrunk)
    }

    @Test func midDragTheNoteGrowsFromItsCurrentCorner() throws {
        let current = CGRect(x: 100, y: 50, width: 300, height: 100) // bottom-left, not saved yet
        let grown = try #require(heightChange(to: 300, from: current, positions: NotePositions(), isDragging: true))
        #expect(grown.minY == current.minY)
        #expect(grown.minX == current.minX)
    }
}
