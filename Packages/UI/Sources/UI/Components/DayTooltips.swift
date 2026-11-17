import Core
import Observation
import SwiftUI

/// Which day's paper tooltip shows in a grid of days (the note's month, the notebook's
/// calendar). The tooltip appears once the pointer has rested on a day briefly.
///
/// Moving between neighboring days can deliver the new day's enter before the old day's exit,
/// so an exit only affects its own day (Phase 4 review).
@Observable
final class DayHover {
    /// The day whose tooltip shows.
    private(set) var shownDay: DayKey?
    @ObservationIgnored private var pendingDay: DayKey?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let delay = Duration.milliseconds(450)

    func hover(_ day: DayKey, _ hovering: Bool) {
        if hovering {
            task?.cancel()
            pendingDay = day
            if shownDay != day { shownDay = nil }
            task = Task { [weak self] in
                try? await Task.sleep(for: Self.delay)
                guard !Task.isCancelled else { return }
                self?.shownDay = day
            }
        } else {
            if pendingDay == day {
                task?.cancel()
                pendingDay = nil
            }
            if shownDay == day { shownDay = nil }
        }
    }

    /// A click opened a card over the grid, so no exit event will come.
    func clear() {
        task?.cancel()
        pendingDay = nil
        shownDay = nil
    }
}

extension View {
    /// Marks this view as `day`'s cell for `dayTooltips` and tracks the pointer over it.
    func dayTooltipCell(_ day: DayKey, hover: DayHover) -> some View {
        anchorPreference(key: DayCellBoundsKey.self, value: .bounds) { [day: $0] }
            .onHover { hover.hover(day, $0) }
    }

    /// Draws the hovered day's tooltip above its cell, kept inside this view's width.
    func dayTooltips(_ hover: DayHover, text: @escaping (DayKey) -> String?) -> some View {
        overlayPreferenceValue(DayCellBoundsKey.self) { bounds in
            GeometryReader { proxy in
                if let day = hover.shownDay, let anchor = bounds[day], let text = text(day) {
                    DayTooltip(text: text, cell: proxy[anchor], width: proxy.size.width)
                }
            }
            .allowsHitTesting(false)
        }
        .onDisappear { hover.clear() }
    }
}

private struct DayCellBoundsKey: PreferenceKey {
    static let defaultValue: [DayKey: Anchor<CGRect>] = [:]
    static func reduce(value: inout [DayKey: Anchor<CGRect>], nextValue: () -> [DayKey: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A small paper label above the hovered day. Drawn by the app itself (not a system tooltip), so
/// it matches the paper and shows even while another app is active (the note never activates).
private struct DayTooltip: View {
    let text: String
    let cell: CGRect
    let width: CGFloat

    @State private var size: CGSize = .zero

    var body: some View {
        Text(text)
            .font(.text(11))
            .foregroundStyle(Palette.ink)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: min(240, width), alignment: .leading)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.track))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .position(x: min(max(cell.midX, size.width / 2), width - size.width / 2),
                      y: cell.minY - 4 - size.height / 2)
            .opacity(size == .zero ? 0 : 1)
            .accessibilityHidden(true) // the cell's label says the same
    }
}
