//
//  LizardPose.swift
//  MonitorLizard
//
//  The stand-in lizard's body layout for one frame (body points, legs, head,
//  eyes, tongue), worked out from the simulation. The 3D renderers use it;
//  points are in screen points, measured from `origin`.
//

import CoreGraphics

nonisolated struct LizardPose {

    struct BodyPoint {
        var center: CGPoint
        var radius: CGFloat
    }

    struct Leg {
        var base: CGPoint
        var knee: CGPoint
        var foot: CGPoint
    }

    var body: [BodyPoint]
    var legs: [Leg]
    var snoutCenter: CGPoint
    /// Direction the head points, in screen terms (radians, y down).
    var headAngle: CGFloat
    var eyes: [CGPoint]
    /// Start and end of the tongue while it's flicking, otherwise nil.
    var tongue: (start: CGPoint, end: CGPoint)?

    init(_ sim: WanderSimulation, relativeTo origin: CGPoint) {
        typealias R = PlaceholderLizardRenderer
        let s = sim.spine.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        let n = s.count

        body = s.indices.map { BodyPoint(center: s[$0], radius: R.halfWidth(at: $0, of: n)) }

        // Same leg rules as the 2D drawing: diagonal pairs step together.
        var legs: [Leg] = []
        let shoulder = Int((CGFloat(n - 1) * 0.14).rounded())
        let hip = Int((CGFloat(n - 1) * 0.40).rounded())
        for (index, isFront) in [(shoulder, true), (hip, false)] {
            let f = R.forward(at: index, in: s)
            let normal = CGVector(dx: -f.dy, dy: f.dx)
            let edge = R.halfWidth(at: index, of: n)
            let reach: CGFloat = isFront ? 3 : -3
            for side: CGFloat in [1, -1] {
                let leadsPair = (isFront ? side : -side) > 0
                let swing = sin(sim.stridePhase + (leadsPair ? 0 : .pi))
                let base = s[index]
                let knee = R.offset(R.offset(base, by: normal, side * (edge + 6)), by: f, swing * 4 + reach * 0.5)
                let foot = R.offset(R.offset(knee, by: normal, side * 4), by: f, swing * 6 + reach)
                legs.append(Leg(base: base, knee: knee, foot: foot))
            }
        }
        self.legs = legs

        let f0 = R.forward(at: 0, in: s)
        let n0 = CGVector(dx: -f0.dy, dy: f0.dx)
        headAngle = atan2(f0.dy, f0.dx)
        snoutCenter = R.offset(s[0], by: f0, 3)
        eyes = [CGFloat(1), -1].map { side in
            R.offset(R.offset(s[0], by: f0, 1.5), by: n0, side * 3.6)
        }
        if !sim.isWalking, sin(sim.pauseRemaining * 10) > 0.6 {
            tongue = (R.offset(s[0], by: f0, 11), R.offset(s[0], by: f0, 19))
        } else {
            tongue = nil
        }
    }
}
