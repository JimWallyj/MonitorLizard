//
//  Ledges.swift
//  MonitorLizard
//
//  Phase 3 step 2: the ledges the lizard can walk along in side view.
//
//  A ledge is a horizontal edge with room above it for the lizard: the top edge
//  of an app window, and the bottom of the screen (the top of the Dock when the
//  Dock is at the bottom). Parts covered by windows in front, or without enough
//  clear space above (the lizard is always behind windows), are left out, and
//  pieces shorter than the lizard are dropped.
//

import CoreGraphics

nonisolated struct Ledge: Equatable, Sendable {
    /// Height of the edge, in habitat coordinates (top-left origin, y down).
    let y: CGFloat
    /// The walkable stretch along the edge.
    let xRange: ClosedRange<CGFloat>
    /// The window whose top edge this is; nil for the screen bottom / Dock top.
    let windowID: Int?

    var length: CGFloat { xRange.upperBound - xRange.lowerBound }
}

nonisolated enum LedgeFinder {

    /// - Parameters:
    ///   - windows: app windows, front to back (as `WindowScanner` returns them).
    ///   - bottomY: the screen bottom, or the top of the Dock.
    ///   - clearance: clear space needed above a ledge for the lizard's body.
    ///   - minLength: shortest usable piece (the lizard is ~131 pt long).
    ///   - topMargin: keep clear of the menu bar.
    static func ledges(windows: [ScreenWindow], bottomY: CGFloat, bounds: CGRect,
                       clearance: CGFloat = 40, minLength: CGFloat = 170,
                       topMargin: CGFloat = 30) -> [Ledge] {
        var candidates: [(y: CGFloat, range: ClosedRange<CGFloat>, id: Int?, blockers: ArraySlice<ScreenWindow>)] = []
        for (k, window) in windows.enumerated() {
            let lo = max(window.frame.minX, bounds.minX), hi = min(window.frame.maxX, bounds.maxX)
            guard hi > lo else { continue }
            candidates.append((window.frame.minY, lo...hi, window.id, windows[..<k]))
        }
        candidates.append((bottomY, bounds.minX...bounds.maxX, nil, windows[...]))

        var result: [Ledge] = []
        for c in candidates {
            guard c.y - clearance >= bounds.minY + topMargin, c.y <= bounds.maxY else { continue }
            // The space just above the edge, where the lizard's body goes.
            let band = CGRect(x: bounds.minX, y: c.y - clearance, width: bounds.width, height: clearance + 4)
            var pieces = [c.range]
            for blocker in c.blockers where blocker.frame.intersects(band) {
                pieces = pieces.flatMap { subtract(blocker.frame.minX...blocker.frame.maxX, from: $0) }
            }
            for piece in pieces where piece.upperBound - piece.lowerBound >= minLength {
                result.append(Ledge(y: c.y, xRange: piece, windowID: c.id))
            }
        }
        return result
    }

    /// `range` with `cut` removed: zero, one or two pieces.
    static func subtract(_ cut: ClosedRange<CGFloat>, from range: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        guard cut.upperBound > range.lowerBound, cut.lowerBound < range.upperBound else { return [range] }
        var pieces: [ClosedRange<CGFloat>] = []
        if cut.lowerBound > range.lowerBound { pieces.append(range.lowerBound...cut.lowerBound) }
        if cut.upperBound < range.upperBound { pieces.append(cut.upperBound...range.upperBound) }
        return pieces
    }

    /// The ledge nearest a point: mostly by height, plus how far outside its stretch the point is.
    static func nearest(to point: CGPoint, in ledges: [Ledge]) -> Ledge? {
        ledges.min { score($0, point) < score($1, point) }
    }

    private static func score(_ ledge: Ledge, _ p: CGPoint) -> CGFloat {
        let outside = max(ledge.xRange.lowerBound - p.x, 0) + max(p.x - ledge.xRange.upperBound, 0)
        return abs(ledge.y - p.y) + outside
    }
}
