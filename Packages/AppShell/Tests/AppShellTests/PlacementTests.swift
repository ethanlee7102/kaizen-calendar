import CoreGraphics
import Foundation
import Testing
@testable import AppShell

// Displays as AppKit sees them: the main display at the origin, an external one to its right.
private let laptop = Display(id: "LAPTOP", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
private let external = Display(id: "EXTERNAL", visibleFrame: CGRect(x: 1440, y: -200, width: 2560, height: 1415))
private let note = CGSize(width: 300, height: 400)

@Suite struct AnchoredPositionTests {
    @Test(arguments: [
        (CGRect(x: 30, y: 40, width: 300, height: 400), Corner.bottomLeft, 30.0, 40.0),
        (CGRect(x: 30, y: 435, width: 300, height: 400), Corner.topLeft, 30.0, 40.0),
        (CGRect(x: 1100, y: 40, width: 300, height: 400), Corner.bottomRight, 40.0, 40.0),
        (CGRect(x: 1100, y: 435, width: 300, height: 400), Corner.topRight, 40.0, 40.0),
    ])
    func anchorsToTheNearestCorner(frame: CGRect, corner: Corner, dx: Double, dy: Double) {
        let position = AnchoredPosition(frame: frame, in: laptop.visibleFrame)
        #expect(position == AnchoredPosition(corner: corner, dx: dx, dy: dy))
        #expect(position.frame(size: frame.size, in: laptop.visibleFrame) == frame)
    }

    @Test func keepsItsCornerWhenTheResolutionChanges() {
        let position = AnchoredPosition(frame: CGRect(x: 1100, y: 435, width: 300, height: 400), in: laptop.visibleFrame)
        let larger = CGRect(x: 0, y: 0, width: 1728, height: 1079)
        #expect(position.frame(size: note, in: larger) == CGRect(x: 1388, y: 639, width: 300, height: 400))
    }

    @Test func growsAwayFromItsCorner() {
        let bottomRight = AnchoredPosition(corner: .bottomRight, dx: 20, dy: 20)
        let short = bottomRight.frame(size: CGSize(width: 300, height: 200), in: laptop.visibleFrame)
        let tall = bottomRight.frame(size: CGSize(width: 300, height: 500), in: laptop.visibleFrame)
        #expect(short.minY == tall.minY) // bottom edge stays, grows upwards
        #expect(tall.maxY > short.maxY)

        let topLeft = AnchoredPosition(corner: .topLeft, dx: 20, dy: 20)
        let shortTop = topLeft.frame(size: CGSize(width: 300, height: 200), in: laptop.visibleFrame)
        let tallTop = topLeft.frame(size: CGSize(width: 300, height: 500), in: laptop.visibleFrame)
        #expect(shortTop.maxY == tallTop.maxY) // top edge stays, grows downwards
    }

    @Test func neverPlacesTheNoteOffScreen() {
        // Saved half off the edge (a drag past the edge), then placed on a smaller display.
        let position = AnchoredPosition(corner: .topRight, dx: -150, dy: 900)
        let frame = position.frame(size: note, in: laptop.visibleFrame)
        #expect(laptop.visibleFrame.contains(frame))
    }
}

@Suite struct ClampTests {
    @Test func movesARectBackInside() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(NoteGeometry.clamp(CGRect(x: -50, y: 700, width: 300, height: 400), to: bounds)
                == CGRect(x: 0, y: 400, width: 300, height: 400))
        #expect(NoteGeometry.clamp(CGRect(x: 900, y: -10, width: 300, height: 400), to: bounds)
                == CGRect(x: 700, y: 0, width: 300, height: 400))
    }

    @Test func leavesARectInsideAlone() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = CGRect(x: 10, y: 10, width: 300, height: 400)
        #expect(NoteGeometry.clamp(rect, to: bounds) == rect)
    }

    @Test func keepsTheTopLeftVisibleWhenTooLarge() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let clamped = NoteGeometry.clamp(CGRect(x: 300, y: -100, width: 880, height: 620), to: bounds)
        #expect(clamped.minX == bounds.minX)
        #expect(clamped.maxY == bounds.maxY)
    }
}

@Suite struct ExpandedFrameTests {
    let size = CGSize(width: 880, height: 620)

    @Test func growsOutOfTheNotesCorner() {
        // Note at the top-right: the notebook keeps the note's top-right corner.
        let topRight = CGRect(x: 1116, y: 451, width: 300, height: 400)
        let expanded = NoteGeometry.expandedFrame(from: topRight, size: size, in: laptop.visibleFrame)
        #expect(expanded.maxX == topRight.maxX)
        #expect(expanded.maxY == topRight.maxY)

        // Note at the bottom-left: the notebook keeps the note's bottom-left corner.
        let bottomLeft = CGRect(x: 24, y: 24, width: 300, height: 400)
        let fromBottom = NoteGeometry.expandedFrame(from: bottomLeft, size: size, in: laptop.visibleFrame)
        #expect(fromBottom.origin == bottomLeft.origin)
    }

    @Test func staysFullyOnScreenNearAnEdge() {
        // A short note in the top-left whose notebook would hang off the bottom.
        let nearEdge = CGRect(x: 0, y: 500, width: 300, height: 120)
        let expanded = NoteGeometry.expandedFrame(from: nearEdge, size: size, in: laptop.visibleFrame)
        #expect(laptop.visibleFrame.contains(expanded))
        #expect(expanded.size == size)
    }
}

@Suite struct NotePositionsTests {
    @Test func startsAtTheTopRightOfTheMainDisplay() throws {
        let frame = try #require(NotePositions().frame(size: note, displays: [laptop, external]))
        #expect(frame == CGRect(x: 1440 - 24 - 300, y: 875 - 24 - 400, width: 300, height: 400))
    }

    @Test func returnsToTheHomeDisplayAfterARelaunch() throws {
        var positions = NotePositions()
        let dragged = CGRect(x: 1600, y: 100, width: 300, height: 400)
        positions.save(frame: dragged, on: external)
        let restored = try #require(positions.frame(size: note, displays: [laptop, external]))
        #expect(restored == dragged)
    }

    @Test func fallsBackToTheMainDisplayInTheSameCornerWhenHomeIsUnplugged() throws {
        var positions = NotePositions()
        positions.save(frame: CGRect(x: 1600, y: -150, width: 300, height: 400), on: external) // bottom-left, 160/50
        let fallback = try #require(positions.frame(size: note, displays: [laptop]))
        #expect(fallback == CGRect(x: 160, y: 50, width: 300, height: 400))
        #expect(positions.home == "EXTERNAL") // unchanged, so replugging returns it
        let replugged = try #require(positions.frame(size: note, displays: [laptop, external]))
        #expect(replugged == CGRect(x: 1600, y: -150, width: 300, height: 400))
    }

    @Test func fallsBackToTheSpotLastChosenOnTheMainDisplay() throws {
        var positions = NotePositions()
        let onLaptop = CGRect(x: 500, y: 300, width: 300, height: 400)
        positions.save(frame: onLaptop, on: laptop)
        positions.save(frame: CGRect(x: 1600, y: -150, width: 300, height: 400), on: external)
        #expect(try #require(positions.frame(size: note, displays: [laptop])) == onLaptop)
    }

    @Test func aDragWhileHomeIsUnpluggedMakesANewHome() throws {
        var positions = NotePositions()
        positions.save(frame: CGRect(x: 1600, y: -150, width: 300, height: 400), on: external)
        let onLaptop = CGRect(x: 500, y: 300, width: 300, height: 400)
        positions.save(frame: onLaptop, on: laptop)
        #expect(try #require(positions.frame(size: note, displays: [laptop, external])) == onLaptop)
    }

    @Test func noDisplaysMeansNoFrame() {
        #expect(NotePositions().frame(size: note, displays: []) == nil)
    }
}

@Suite struct PositionStoreTests {
    private func makeStore() -> (PositionStore, UserDefaults) {
        let suite = "AppShellTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (PositionStore(defaults: defaults), defaults)
    }

    @Test func roundTripsAndResets() {
        let (store, _) = makeStore()
        var positions = NotePositions()
        positions.save(frame: CGRect(x: 1600, y: 100, width: 300, height: 400), on: external)
        store.positions = positions
        #expect(store.positions == positions)
        store.reset()
        #expect(store.positions == NotePositions())
    }

    @Test func unreadableDataCountsAsNoPositions() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not json".utf8), forKey: "note.positions")
        #expect(store.positions == NotePositions())
    }
}
