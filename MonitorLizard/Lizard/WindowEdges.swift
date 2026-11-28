//
//  WindowEdges.swift
//  MonitorLizard
//
//  Phase 1 step 5: the lizard notices your windows and walks along their edges.
//
//  • WindowScanner asks macOS where the ordinary app windows are. Only window
//    positions and sizes are read (no titles or contents), which needs no
//    permission and works inside the App Sandbox.
//  • EdgePlanner turns a window into a short walk: from one corner of the
//    window's outline, along one or two of its sides, just outside the edge so
//    the lizard's near legs grip the edge.
//

import CoreGraphics
import Foundation

/// An ordinary app window on screen, in habitat coordinates (top-left origin, y down).
nonisolated struct ScreenWindow: Equatable, Sendable {
    let id: Int
    let frame: CGRect
}

enum WindowScanner {
    static let followEdgesKey = "lizardFollowEdges"

    /// On-screen windows of normal apps (window layer 0), front to back.
    /// Tiny windows (under 120 × 80 points) are skipped.
    static func normalWindows() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 120, frame.height >= 80
            else { return nil }
            return ScreenWindow(id: number, frame: frame)
        }
    }
}

extension WindowScanner {
    /// One window's current frame (cheap: asks about that window only). nil if it's gone or hidden.
    static func frame(ofWindow id: Int) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]],
              let info = list.first,
              (info[kCGWindowIsOnscreen as String] as? Bool) ?? true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return frame
    }
}

nonisolated struct EdgePlanner {
    /// Distance from the window edge to the lizard's centreline. About the
    /// width of its legs, so the near feet sit right at the edge.
    var offset: CGFloat = 14
    /// Corners closer than this to the screen edge aren't used.
    var margin: CGFloat = 20

    private var rng: SeededRandom

    init(seed: UInt64 = .random(in: .min ... .max)) {
        rng = SeededRandom(seed: seed)
    }

    /// Waypoints that walk along one or two sides of the window's outline,
    /// starting at a random corner, clockwise or anticlockwise.
    /// Returns nil if no side of the window is fully on screen.
    /// - Parameter startNear: if given, start at the usable corner nearest this point
    ///   (so routes chain around a window instead of cutting behind it).
    mutating func plan(around window: CGRect, in bounds: CGRect, startNear: CGPoint? = nil) -> [CGPoint]? {
        let r = window.insetBy(dx: -offset, dy: -offset)
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        let area = bounds.insetBy(dx: margin, dy: margin)
        let step = Bool.random(using: &rng) ? 1 : 3                 // clockwise or anticlockwise
        let preferredSides = Int.random(in: 1...2, using: &rng)

        for sides in Set([preferredSides, 1]).sorted(by: >) {
            let order: [Int]
            if let p = startNear {
                order = (0..<4).sorted { hypot(corners[$0].x - p.x, corners[$0].y - p.y)
                                       < hypot(corners[$1].x - p.x, corners[$1].y - p.y) }
            } else {
                order = (0..<4).shuffled(using: &rng)
            }
            for start in order {
                var points = [corners[start]]
                var k = start
                for _ in 0..<sides {
                    k = (k + step) % 4
                    points.append(corners[k])
                }
                if points.allSatisfy({ area.contains($0) }) { return points }
            }
        }
        return nil
    }

    /// Shortest distance from a point to a rectangle (0 if inside).
    static func distance(from p: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return hypot(dx, dy)
    }
}
