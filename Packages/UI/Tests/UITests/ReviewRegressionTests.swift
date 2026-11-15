import Core
import SwiftUI
import Testing
@testable import UI

/// Regression tests for the Phase 4 code review (build-plan.md, Phase 4). Each one failed before
/// its fix.
@Suite struct ReviewRegressionTests {
    // A3: a field that kept focus after saving could later write its old text over a newer note.
    @Test func noteFieldNeverSavesTextItAlreadySaved() {
        var draft = NoteDraft()
        draft.typed("A")
        #expect(draft.commit(stored: "") == "A")
        draft.storedChanged() // the save lands: stored is "A"
        draft.storedChanged() // another place changes it to "B" while this field is still focused
        #expect(draft.display(stored: "B") == "B", "Follows the stored note while nothing is unsaved")
        #expect(draft.commit(stored: "B") == nil, "Leaving the field later must not write \"A\" back")
    }

    @Test func noteFieldDoesNotResaveBeforeTheOutsideChangeArrives() {
        var draft = NoteDraft()
        draft.typed("A")
        #expect(draft.commit(stored: "") == "A")
        // The note became "B" elsewhere and the field loses focus before it has heard about it.
        #expect(draft.commit(stored: "B") == nil)
    }

    @Test func noteFieldKeepsUnsavedTypingOverOutsideChanges() {
        var draft = NoteDraft()
        draft.typed("Walk after lun")
        draft.storedChanged() // something else changed the note mid-typing
        #expect(draft.display(stored: "other") == "Walk after lun", "Typing in progress isn't replaced")
        #expect(draft.commit(stored: "other") == "Walk after lun")
        #expect(draft.commit(stored: "Walk after lun") == nil, "Saved once")
    }

    // A5 / C3: a card opened editable stays editable across midnight (user's choice).
    @Test func cardOpenedEditableStaysEditableUntilClosed() {
        let editing = DayCardEditing(openedAs: .editable)
        #expect(editing.isEditable(now: .editable))
        #expect(!editing.needsChangeAnyway(now: .editable))
        // Midnight: the day is now 3 days old.
        #expect(editing.isEditable(now: .readOnly), "Typing in progress isn't lost")
        #expect(editing.needsChangeAnyway(now: .readOnly), "Writes now need change-anyway, or the repository rejects them")
        #expect(!editing.showsReadOnlyNotice(now: .readOnly))
    }

    @Test func cardOpenedReadOnlyNeedsChangeAnyway() {
        var editing = DayCardEditing(openedAs: .readOnly)
        #expect(!editing.isEditable(now: .readOnly))
        #expect(editing.showsReadOnlyNotice(now: .readOnly))
        editing.unlocked = true
        #expect(editing.isEditable(now: .readOnly))
        #expect(editing.needsChangeAnyway(now: .readOnly))
        #expect(!editing.showsReadOnlyNotice(now: .readOnly))
    }

    // C4: a target of 0 explains why "Add habit" is off.
    @Test func targetOfZeroShowsAHint() {
        var draft = HabitDraft()
        #expect(draft.targetHint == nil)
        draft.target = "0"
        #expect(draft.targetHint == "At least 1.")
        draft.target = "000"
        #expect(draft.targetHint == "At least 1.")
        draft.target = "5"
        #expect(draft.targetHint == nil)
        draft.target = "0"
        draft.kind = .yesNo
        #expect(draft.targetHint == nil, "Just do it has no target")
    }

    // B6: a habit created "tomorrow" (today moved backwards) read "0-day streak" and "next:".
    @Test func habitCreatedTomorrowSaysWhenItStarts() {
        let today = d("2026-11-14")
        let habit = noteHabit("Swim", schedule: Schedule([.sunday, .monday])!, created: "2026-11-15", today: today)
        let input = NoteInput(today: today, habits: [habit])
        #expect(input.rows[0].subtitle == "2 days a week · starts tomorrow")
        #expect(input.rows[0].check == .next("next: Sun"), "Nothing is scheduled today, so it shows its first day")
        #expect(!input.rows[0].canToggle)
    }
}

/// The SVG path parser behind the artwork (B5: no unit tests; tabs weren't separators).
@Suite struct SVGPathTests {
    private func points(_ data: String) -> [CGPoint] {
        var result: [CGPoint] = []
        SVGPath(data).path.forEach { element in
            switch element {
            case .move(let p), .line(let p): result.append(p)
            case .curve(let p, _, _), .quadCurve(let p, _): result.append(p)
            case .closeSubpath: break
            }
        }
        return result
    }

    /// Paths keep coordinates in single precision.
    private func close(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < 0.0001 && abs($0.y - $1.y) < 0.0001 }
    }

    @Test func absoluteAndRelativeLinesWithImplicitRepeats() {
        #expect(points("M5 8.5 11.5 13 9.5 17.5") == [CGPoint(x: 5, y: 8.5), CGPoint(x: 11.5, y: 13), CGPoint(x: 9.5, y: 17.5)])
        #expect(points("m1 1 2 0 0 2") == [CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 1), CGPoint(x: 3, y: 3)])
        #expect(points("M9.5 2.5h4v4") == [CGPoint(x: 9.5, y: 2.5), CGPoint(x: 13.5, y: 2.5), CGPoint(x: 13.5, y: 6.5)])
    }

    @Test func compactNumbersAndRelativeCurves() {
        // "4.2.1" is 4.2 then .1; "-.5" is -0.5.
        let p = points("M18 3.5c4.2.1 8.3 1.9 10.9 5.1-.5 4.1-2.8 7.9-6.2 10.1z")
        #expect(close(p, [CGPoint(x: 18, y: 3.5), CGPoint(x: 28.9, y: 8.6), CGPoint(x: 22.7, y: 18.7)]), "\(p)")
    }

    @Test func tabsAndNewlinesSeparateLikeSpaces() {
        #expect(points("M0\t0L5\t5\n10,10") == [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 10)])
    }

    @Test func arcsEndOnTheirEndpoint() {
        let p = points("M13 2 A11 11 0 1 1 13 24")
        let end = try! #require(p.last)
        #expect(abs(end.x - 13) < 0.001 && abs(end.y - 24) < 0.001)
        // Sweep 1 from the top goes clockwise on screen: through the right side (x > 13).
        #expect(p.dropFirst().dropLast().allSatisfy { $0.x >= 13 - 0.001 })
    }
}
