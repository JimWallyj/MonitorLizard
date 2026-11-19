//
//  WanderSimulation.swift
//  MonitorLizard
//
//  Phase 1 placeholder movement. A head wanders toward random targets with a
//  water monitor's side-to-side "sashay", occasionally stopping to look
//  around, and the spine follows it like a chain. This is the seed of the
//  procedural animation that will later drive the real 3D model's skeleton.
//
//  Marked `nonisolated` because it is plain math with no UI, and it's called
//  from SwiftUI's Canvas drawing code.
//

import CoreGraphics
import Foundation

/// A small seedable random number generator (SplitMix64), so a simulation can
/// be replayed exactly in tests.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

nonisolated struct WanderSimulation {

    struct Config {
        var walkSpeed: CGFloat = 35              // points per second (a slow, deliberate walk)
        var maxTurnRate: CGFloat = 1.4           // radians per second
        var segmentCount = 16                    // spine points, head first
        var segmentSpacing: CGFloat = 8          // points between spine points
        var margin: CGFloat = 60                 // stay this far from the screen edges
        var arrivalDistance: CGFloat = 30        // "close enough" to a target
        var strideLength: CGFloat = 36           // distance for one full leg cycle
        var swayAmount: CGFloat = 0.35           // radians of side-to-side sashay
        var pauseChance: Double = 0.35           // chance of stopping on reaching a target
        var pauseRange: ClosedRange<Double> = 0.8...3.0   // seconds
        var maxTimeStep: Double = 0.1            // longer gaps (e.g. after Pause) are clamped
        var waypointArrival: CGFloat = 10        // "close enough" to a waypoint on a planned route
        var routeTurnRate: CGFloat = 3.0         // sharper turns on a route, to round window corners
    }

    let config: Config

    /// Spine points from the head (index 0) to the tail tip.
    private(set) var spine: [CGPoint]
    /// Direction the head is travelling, in radians (sway not included).
    private(set) var heading: CGFloat
    /// Where the lizard is currently heading.
    private(set) var target: CGPoint
    /// 0 ..< 2π; advances with distance walked and drives the legs and sway.
    private(set) var stridePhase: CGFloat = 0
    /// Seconds left in the current "stop and look around" pause.
    private(set) var pauseRemaining: Double = 0

    private var rng: SeededRandom
    /// A planned route (e.g. along a window edge), followed in order before wandering resumes.
    private(set) var waypoints: [CGPoint] = []

    var head: CGPoint { spine[0] }
    var isWalking: Bool { pauseRemaining <= 0 }
    var isFollowingRoute: Bool { !waypoints.isEmpty }

    /// Side view: pick wander targets only to the left or right, so the lizard stays in profile.
    var levelWalking = false
    /// Areas wander targets should avoid (e.g. windows, so it doesn't head behind them).
    var obstacles: [CGRect] = []

    /// Walk through `points` in order (an empty list cancels the current route).
    mutating func follow(_ points: [CGPoint]) {
        waypoints = points
        if let first = points.first { target = first }
    }

    init(start: CGPoint,
         heading: CGFloat = 0,
         bounds: CGRect,
         config: Config = Config(),
         seed: UInt64 = .random(in: .min ... .max)) {
        self.config = config
        self.heading = heading
        self.rng = SeededRandom(seed: seed)

        // Lay the spine out in a straight line behind the head.
        let backX = -cos(heading), backY = -sin(heading)
        spine = (0..<max(config.segmentCount, 2)).map { i in
            let distance = config.segmentSpacing * CGFloat(i)
            return CGPoint(x: start.x + backX * distance, y: start.y + backY * distance)
        }

        target = start
        target = randomTarget(in: bounds)
    }

    /// Advance the simulation by `rawDelta` seconds inside `bounds`.
    mutating func step(by rawDelta: Double, in bounds: CGRect) {
        let dt = min(max(rawDelta, 0), config.maxTimeStep)
        guard dt > 0 else { return }

        if pauseRemaining > 0 {
            pauseRemaining -= dt
            return
        }

        // Pick a new target on arrival, or if the screen changed size and
        // the old target is now out of reach. Sometimes stop for a look first.
        let area = walkableArea(in: bounds)
        if !waypoints.isEmpty {
            // On a route: head for the next waypoint; at the end, maybe stop for a look.
            if Self.distance(head, waypoints[0]) < config.waypointArrival {
                waypoints.removeFirst()
                if waypoints.isEmpty {
                    if Double.random(in: 0..<1, using: &rng) < config.pauseChance {
                        pauseRemaining = Double.random(in: config.pauseRange, using: &rng)
                    }
                    target = randomTarget(in: bounds)
                    if pauseRemaining > 0 { return }
                } else {
                    target = waypoints[0]
                }
            } else {
                target = waypoints[0]
            }
        } else if !area.contains(target) || Self.distance(head, target) < config.arrivalDistance {
            if area.contains(target), Double.random(in: 0..<1, using: &rng) < config.pauseChance {
                pauseRemaining = Double.random(in: config.pauseRange, using: &rng)
            }
            target = randomTarget(in: bounds)
            if pauseRemaining > 0 { return }
        }

        // Turn toward the target, no faster than the maximum turn rate.
        let desired = atan2(target.y - head.y, target.x - head.x)
        let turn = Self.normalizedAngle(desired - heading)
        let maxTurn = (waypoints.isEmpty ? config.maxTurnRate : config.routeTurnRate) * CGFloat(dt)
        heading = Self.normalizedAngle(heading + min(max(turn, -maxTurn), maxTurn))

        // Step forward, swaying side to side in time with the stride.
        let distanceMoved = config.walkSpeed * CGFloat(dt)
        let direction = heading + sin(stridePhase) * config.swayAmount
        let newHead = CGPoint(
            x: min(max(head.x + cos(direction) * distanceMoved, bounds.minX), bounds.maxX),
            y: min(max(head.y + sin(direction) * distanceMoved, bounds.minY), bounds.maxY))
        spine[0] = newHead
        stridePhase = (stridePhase + distanceMoved / config.strideLength * 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)

        // Each spine point follows the one in front of it at a fixed spacing.
        for i in 1..<spine.count {
            let dx = spine[i].x - spine[i - 1].x
            let dy = spine[i].y - spine[i - 1].y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            let scale = config.segmentSpacing / length
            spine[i] = CGPoint(x: spine[i - 1].x + dx * scale, y: spine[i - 1].y + dy * scale)
        }
    }

    // MARK: - Helpers

    private func walkableArea(in bounds: CGRect) -> CGRect {
        let inset = bounds.insetBy(dx: config.margin, dy: config.margin)
        return (inset.isNull || inset.isEmpty) ? bounds : inset
    }

    private mutating func randomTarget(in bounds: CGRect) -> CGPoint {
        let area = walkableArea(in: bounds)
        var candidate = head
        for _ in 0..<10 {
            candidate = CGPoint(x: CGFloat.random(in: area.minX...area.maxX, using: &rng),
                                y: CGFloat.random(in: area.minY...area.maxY, using: &rng))
            if levelWalking { candidate.y = min(max(head.y, area.minY), area.maxY) }
            if !obstacles.contains(where: { $0.insetBy(dx: -30, dy: -30).contains(candidate) }) { break }
        }
        return candidate
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Wraps an angle into -π ... π.
    static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi } else if a < -.pi { a += 2 * .pi }
        return a
    }
}
