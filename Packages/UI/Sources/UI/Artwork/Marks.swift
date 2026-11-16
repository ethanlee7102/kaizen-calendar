import Core
import SwiftUI

/// What a calendar cell shows (spec-collapsed-note.md §3), in either view: all habits or one
/// habit (filtered). Built from Core's `AllHabitsMark` / `SingleHabitMark`.
nonisolated public enum DayCellMark: Hashable, Sendable {
    case fullSeal
    /// One slice per habit scheduled that day, in habit order; true = inked (done).
    case slicedSeal(inked: [Bool])
    case pencilCircle
    case restDash
    case goldSeam
    /// Filtered view, today, not done yet: the number in bold indigo.
    case todayPending
    case faint
    case future

    public init(_ mark: AllHabitsMark) {
        self = switch mark {
        case .fullSeal: .fullSeal
        case .slicedSeal(let slices): .slicedSeal(inked: slices.map(\.isInked))
        case .pencilCircle: .pencilCircle
        case .restDash: .restDash
        case .faint: .faint
        case .future: .future
        }
    }

    public init(_ mark: SingleHabitMark) {
        self = switch mark {
        case .fullSeal: .fullSeal
        case .goldSeam: .goldSeam
        case .pencilCircle: .pencilCircle
        case .restDash: .restDash
        case .todayPending: .todayPending
        case .faint: .faint
        case .future: .future
        }
    }
}

/// One calendar day: its mark, its number, and the indigo frame on today.
public struct DayCellView: View {
    public let day: Int
    public let mark: DayCellMark
    public let isToday: Bool

    public init(day: Int, mark: DayCellMark, isToday: Bool) {
        self.day = day
        self.mark = mark
        self.isToday = isToday
    }

    public var body: some View {
        ZStack {
            if isToday {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Palette.indigo, lineWidth: 1.6)
                    .frame(width: 30, height: 30)
            }
            artwork
            number
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.gridRowHeight, maxHeight: Metrics.gridRowHeight)
    }

    @ViewBuilder private var artwork: some View {
        switch mark {
        case .fullSeal:
            ZStack {
                SealShape().fill(Palette.vermilion)
                // The mockup's inner ring: r 11.5 in the 36-point artwork.
                Circle()
                    .inset(by: 26 * (18 - 11.5) / 36)
                    .stroke(Palette.paper, lineWidth: 0.8)
                    .opacity(0.55)
            }
            .frame(width: 26, height: 26)
            .rotationEffect(.degrees(-6))
        case .slicedSeal(let inked):
            SlicedSeal(inked: inked)
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(-6))
        case .pencilCircle:
            Circle()
                .stroke(Palette.pencil, style: StrokeStyle(lineWidth: 1.3, dash: [2.6, 2.2]))
                .frame(width: 22, height: 22)
        case .restDash:
            Capsule()
                .fill(Palette.moss)
                .frame(width: 9, height: 2)
                .offset(y: 11)
        case .goldSeam:
            GoldSeamShape()
                .stroke(Palette.gold, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                .frame(width: 36, height: 32)
        case .todayPending, .faint, .future:
            EmptyView()
        }
    }

    @ViewBuilder private var number: some View {
        let text = Text(String(day)).monospacedDigit()
        switch mark {
        case .fullSeal:
            text.font(.text(11.5, weight: .bold)).foregroundStyle(Palette.onSeal)
        case .slicedSeal:
            text.font(.text(11.5, weight: .bold)).foregroundStyle(Palette.ink)
                .modifier(PaperHalo())
        case .goldSeam:
            text.font(.text(11.5, weight: .medium)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 2)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 3))
        case .pencilCircle:
            text.font(.text(11.5, weight: .medium)).foregroundStyle(Palette.ink)
        case .todayPending:
            text.font(.text(11.5, weight: .bold)).foregroundStyle(Palette.indigo)
        case .restDash, .future:
            text.font(.text(11.5)).foregroundStyle(Palette.inkFaint)
        case .faint:
            text.font(.text(11.5)).foregroundStyle(Palette.inkFaint)
        }
    }
}

/// A paper-colored glow around text drawn over artwork, so it stays readable.
private struct PaperHalo: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let paper = Palette.paper.color(for: scheme)
        content
            .shadow(color: paper, radius: 1)
            .shadow(color: paper, radius: 1)
            .shadow(color: paper, radius: 1.5)
    }
}

/// A faint vermilion circle split into one slice per scheduled habit; done slices are inked.
struct SlicedSeal: View {
    let inked: [Bool]

    var body: some View {
        ZStack {
            Circle().fill(Palette.vermilion.opacity(0.10))
            ForEach(inked.indices, id: \.self) { index in
                if inked[index] {
                    SealSliceShape(index: index, count: inked.count).fill(Palette.vermilion)
                }
            }
            SealDividers(count: inked.count).stroke(Palette.paper, lineWidth: 1)
            Circle().stroke(Palette.vermilion.opacity(0.45), lineWidth: 0.9)
        }
    }
}

// MARK: - Leaf on water

/// The check-off control's look (spec-collapsed-note.md §5).
nonisolated public enum LeafState: Hashable, Sendable {
    /// Done: the solid moss leaf.
    case checked
    /// Not done yet: a dashed pencil outline.
    case unchecked
    /// Rested today: the pool with a short moss dash.
    case rested
    /// Not scheduled today: only a dimmed pool.
    case dimmed
}

/// A leaf on its water pool.
public struct LeafMark: View {
    public let state: LeafState
    public var size: CGFloat

    public init(state: LeafState, size: CGFloat = 38) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        ZStack {
            WaterPool()
                .frame(width: size * 42 / 38, height: size * 42 / 38)
                .opacity(state == .dimmed ? 0.5 : 1)
            switch state {
            case .checked:
                ZStack {
                    LeafShape().fill(Palette.moss)
                    LeafVeinShape().stroke(Palette.paper, style: StrokeStyle(lineWidth: 1.1 * size / 36, lineCap: .round))
                        .opacity(0.7)
                    LeafStemShape().stroke(Palette.moss, style: StrokeStyle(lineWidth: 1.6 * size / 36, lineCap: .round))
                }
                .rotationEffect(.degrees(40))
                .frame(width: size, height: size)
            case .unchecked:
                ZStack {
                    LeafShape().stroke(Palette.pencil, style: StrokeStyle(lineWidth: 1.2 * size / 36, lineJoin: .round,
                                                                         dash: [2.6 * size / 36, 2 * size / 36]))
                    LeafVeinShape().stroke(Palette.pencil.opacity(0.6), style: StrokeStyle(lineWidth: 0.9 * size / 36, lineCap: .round))
                    LeafStemShape().stroke(Palette.pencil, style: StrokeStyle(lineWidth: 1.2 * size / 36, lineCap: .round,
                                                                             dash: [2.6 * size / 36, 2 * size / 36]))
                }
                .rotationEffect(.degrees(40))
                .frame(width: size, height: size)
            case .rested:
                Capsule().fill(Palette.moss).frame(width: 14 * size / 38, height: 3)
            case .dimmed:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}

/// A round, soft blue wash, strongest in the middle and fading out. No lines, no rim.
public struct WaterPool: View {
    public init() {}

    public var body: some View {
        // Relative to the pool's frame, so it scales with the leaf.
        Circle().fill(EllipticalGradient(
            stops: [
                .init(color: Palette.water.light.color.opacity(0.26), location: 0),
                .init(color: Palette.water.light.color.opacity(0.18), location: 0.55),
                .init(color: Palette.water.light.color.opacity(0), location: 1),
            ],
            center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
    }
}

private extension RGBA {
    var color: Color { Color(resolved) }
}

// MARK: - Journey

/// The journey's brush circle with "Day N" under it (spec-collapsed-note.md §2). After day 66
/// the circle is closed and a ✓66 badge shows (memory/after-day-66.md).
public struct JourneyBadge: View {
    public let journey: Journey

    public init(journey: Journey) { self.journey = journey }

    public var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle().stroke(Palette.track, lineWidth: 2.4)
                BrushArc(progress: journey.progress)
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                if journey.hasReached66 {
                    Text("✓66")
                        .font(.text(8.5, weight: .bold))
                        .foregroundStyle(Palette.vermilion)
                }
            }
            .padding(1.5)
            .frame(width: 27, height: 27)
            Text("Day \(journey.count)")
                .font(.text(10))
                .monospacedDigit()
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneyBadge.accessibilityText(journey))
    }

    nonisolated static func accessibilityText(_ journey: Journey) -> String {
        journey.hasReached66 ? "Day \(journey.count). Past day 66." : "Day \(journey.count) of 66"
    }
}
