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
        /// How high the foot is lifted mid-step (points); 0 when planted.
        var lift: CGFloat = 0
    }

    var body: [BodyPoint]
    var legs: [Leg]
    var snoutCenter: CGPoint
    /// Direction the head points, in screen terms (radians, y down).
    var headAngle: CGFloat
    var eyes: [CGPoint]
    /// Start and end of the tongue while it's flicking, otherwise nil.
    var tongue: (start: CGPoint, end: CGPoint)?

    // Step 4 (used by the real model): which view to show and where the head looks.
    var view: LizardView = .top
    /// 0 = looking ahead, 1 = looking straight at the viewer.
    var lookAtViewer: CGFloat = 0
    /// Sideways glance, radians.
    var glance: CGFloat = 0
    /// The mouse pointer, in the same coordinates as the body (nil if unknown).
    var pointer: CGPoint?

    // Phase 2 step 3 (real model): the forked tongue.
    var tongueShape = TongueFlick.Shape()

    // Phase 2 step 4 (real model): breathing. 0…1 at natural strength (more if exaggerated).
    var breath: CGFloat = 0
    var throat: CGFloat = 0

    /// - Parameter gait: planted feet and tail wave (step 3). Without it, the
    ///   legs swing in place as in the 2D drawing.
    init(_ sim: WanderSimulation, gait: LizardGait? = nil, relativeTo origin: CGPoint) {
        typealias R = PlaceholderLizardRenderer
        let s = sim.spine.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        let n = s.count

        // Body, with the tail swinging in a wave that travels toward the tip.
        var body = s.indices.map { BodyPoint(center: s[$0], radius: R.halfWidth(at: $0, of: n)) }
        if let gait, gait.tailAmplitude > 0 {
            for i in s.indices {
                let t = CGFloat(i) / CGFloat(max(n - 1, 1))
                guard t > 0.45 else { continue }
                let u = (t - 0.45) / 0.55                       // 0 at the tail base, 1 at the tip
                let f = R.forward(at: i, in: s)
                let sway = gait.tailAmplitude * u * sin(gait.tailPhase - u * 2.5)
                body[i].center = R.offset(s[i], by: CGVector(dx: -f.dy, dy: f.dx), sway)
            }
        }
        self.body = body

        if let gait {
            let shift = CGVector(dx: -origin.x, dy: -origin.y)
            self.legs = gait.feet.indices.map { i in
                let anchor = gait.anchor(for: i, spine: s)
                let foot = R.offset(gait.feet[i].position, by: shift, 1)
                let knee = LizardGait.knee(anchor: anchor, foot: foot,
                                           upper: gait.config.upperLength, lower: gait.config.lowerLength,
                                           bend: gait.bendDirection(for: i, spine: s))
                return Leg(base: anchor, knee: knee, foot: foot, lift: gait.feet[i].lift)
            }
        } else {
            self.legs = Self.swingingLegs(sim, spine: s)
        }

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

    /// Step 1 legs: swing in place with the stride (used by the 2D drawing and tests).
    private static func swingingLegs(_ sim: WanderSimulation, spine s: [CGPoint]) -> [Leg] {
        typealias R = PlaceholderLizardRenderer
        let n = s.count
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
        return legs
    }
}
