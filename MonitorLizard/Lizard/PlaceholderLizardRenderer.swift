//
//  PlaceholderLizardRenderer.swift
//  MonitorLizard
//
//  Draws the Phase 1 stand-in lizard, seen from above, from the simulation's
//  spine: a tapered body, diagonal-pair legs, yellow speckles, eyes, and a
//  forked tongue that flicks while it pauses. Replaced by the 3D model later.
//

import SwiftUI

nonisolated enum PlaceholderLizardRenderer {

    private static let skin = Color(red: 0.22, green: 0.22, blue: 0.14)
    private static let speckle = Color(red: 0.86, green: 0.78, blue: 0.38)
    private static let tongueColor = Color(red: 0.58, green: 0.45, blue: 0.78)
    private static var legStyle: StrokeStyle {
        StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
    }

    static func draw(_ sim: WanderSimulation, in context: inout GraphicsContext) {
        let spine = sim.spine
        guard spine.count >= 3 else { return }

        // Draw into one layer so the soft drop shadow is cast by the whole lizard.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 3, x: 3, y: 5))
            layer.stroke(legs(sim), with: .color(skin), style: legStyle)
            layer.fill(body(spine), with: .color(skin))
            layer.fill(snout(spine), with: .color(skin))
            layer.fill(speckles(spine), with: .color(speckle))
            layer.fill(eyes(spine), with: .color(.black))
            if let tongue = tongue(sim) {
                layer.stroke(tongue, with: .color(tongueColor),
                             style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
    }

    // MARK: - Shape

    /// Half the body's width at each spine point: head, neck, body bulge, tapering tail.
    private static func halfWidth(at index: Int, of count: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(max(count - 1, 1))   // 0 = head, 1 = tail tip
        switch t {
        case ..<0.06: return 5.5
        case ..<0.14: return 4.5
        case ..<0.45: return 4.5 + 4.0 * sin((t - 0.14) / 0.31 * .pi)
        default:      return max(4.5 * (1 - (t - 0.45) / 0.55), 0.6)
        }
    }

    private static func body(_ spine: [CGPoint]) -> Path {
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in spine.indices {
            let f = forward(at: i, in: spine)
            let r = halfWidth(at: i, of: spine.count)
            left.append(offset(spine[i], by: CGVector(dx: -f.dy, dy: f.dx), r))
            right.append(offset(spine[i], by: CGVector(dx: f.dy, dy: -f.dx), r))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    private static func snout(_ spine: [CGPoint]) -> Path {
        let f = forward(at: 0, in: spine)
        let center = offset(spine[0], by: f, 3)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: atan2(f.dy, f.dx))
        return Path(ellipseIn: CGRect(x: -8, y: -5, width: 16, height: 10)).applying(transform)
    }

    /// Four legs. Diagonal pairs (front-left with back-right) step together.
    private static func legs(_ sim: WanderSimulation) -> Path {
        let spine = sim.spine
        let n = spine.count
        let shoulder = Int((CGFloat(n - 1) * 0.14).rounded())
        let hip = Int((CGFloat(n - 1) * 0.40).rounded())
        var path = Path()

        for (index, isFront) in [(shoulder, true), (hip, false)] {
            let f = forward(at: index, in: spine)
            let normal = CGVector(dx: -f.dy, dy: f.dx)
            let edge = halfWidth(at: index, of: n)
            let reach: CGFloat = isFront ? 3 : -3

            for side: CGFloat in [1, -1] {
                let leadsPair = (isFront ? side : -side) > 0
                let swing = sin(sim.stridePhase + (leadsPair ? 0 : .pi))   // -1 ... 1
                let base = spine[index]
                let knee = offset(offset(base, by: normal, side * (edge + 6)), by: f, swing * 4 + reach * 0.5)
                let foot = offset(offset(knee, by: normal, side * 4), by: f, swing * 6 + reach)
                path.move(to: base)
                path.addLine(to: knee)
                path.addLine(to: foot)
                path.addEllipse(in: CGRect(x: foot.x - 1.8, y: foot.y - 1.8, width: 3.6, height: 3.6))
            }
        }
        return path
    }

    private static func speckles(_ spine: [CGPoint]) -> Path {
        var path = Path()
        guard spine.count > 4 else { return path }
        for i in 2..<(spine.count - 2) {
            let f = forward(at: i, in: spine)
            let normal = CGVector(dx: -f.dy, dy: f.dx)
            let r = halfWidth(at: i, of: spine.count)
            for side: CGFloat in (i.isMultiple(of: 2) ? [0.45, -0.1] : [-0.45, 0.15]) {
                let p = offset(spine[i], by: normal, r * side)
                let dot = max(r * 0.16, 0.5)
                path.addEllipse(in: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2))
            }
        }
        return path
    }

    private static func eyes(_ spine: [CGPoint]) -> Path {
        let f = forward(at: 0, in: spine)
        let normal = CGVector(dx: -f.dy, dy: f.dx)
        var path = Path()
        for side: CGFloat in [1, -1] {
            let p = offset(offset(spine[0], by: f, 1.5), by: normal, side * 3.6)
            path.addEllipse(in: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2))
        }
        return path
    }

    /// A quick forked-tongue flick, only while the lizard is stopped.
    private static func tongue(_ sim: WanderSimulation) -> Path? {
        guard !sim.isWalking, sin(sim.pauseRemaining * 10) > 0.6 else { return nil }
        let spine = sim.spine
        let f = forward(at: 0, in: spine)
        let tip = offset(spine[0], by: f, 11)
        let fork = offset(tip, by: f, 8)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: fork)
        for angle: CGFloat in [0.45, -0.45] {
            let dir = CGVector(dx: f.dx * cos(angle) - f.dy * sin(angle),
                               dy: f.dx * sin(angle) + f.dy * cos(angle))
            path.move(to: fork)
            path.addLine(to: offset(fork, by: dir, 3))
        }
        return path
    }

    // MARK: - Vector helpers

    /// Unit vector pointing toward the head at spine point `i`.
    private static func forward(at i: Int, in spine: [CGPoint]) -> CGVector {
        let a = spine[max(i - 1, 0)]
        let b = spine[min(i + 1, spine.count - 1)]
        let dx = a.x - b.x, dy = a.y - b.y
        let length = hypot(dx, dy)
        return length > 0 ? CGVector(dx: dx / length, dy: dy / length) : CGVector(dx: 1, dy: 0)
    }

    private static func offset(_ p: CGPoint, by v: CGVector, _ k: CGFloat) -> CGPoint {
        CGPoint(x: p.x + v.dx * k, y: p.y + v.dy * k)
    }
}
