//
//  LizardGait.swift
//  MonitorLizard
//
//  Phase 1 step 3: a lizard's walk. Each foot stays planted where it landed
//  while the body moves over it. When a foot falls too far behind its natural
//  spot beside the body, it lifts and steps forward. Diagonal pairs step
//  together (front-left with back-right, then front-right with back-left), and
//  a pair never lifts while the other pair is in the air. When the lizard
//  stops, the feet take small settling steps. The tail swings in a wave.
//
//  Works purely on positions, so the same logic will drive the real model's
//  leg and tail bones later.
//

import CoreGraphics
import Foundation

nonisolated struct LizardGait {

    struct Config: Equatable {
        // Real-model overrides (set from the rigged model's measurements; nil = stand-in values).
        var frontSpineIndex: Int? = nil       // spine point the front legs hang from
        var backSpineIndex: Int? = nil        // spine point the back legs hang from
        var frontLateral: CGFloat? = nil      // front feet rest this far from the centreline
        var backLateral: CGFloat? = nil       // back feet rest this far from the centreline

        var upperLength: CGFloat = 8          // shoulder/hip to elbow/knee, points
        var lowerLength: CGFloat = 7.5        // elbow/knee to foot
        var footSpread: CGFloat = 11          // feet rest this far outside the body edge
        var frontReach: CGFloat = 4           // front feet rest a little ahead of the shoulder
        var backReach: CGFloat = -3           // back feet rest a little behind the hip
        var stepTrigger: CGFloat = 11         // how far a foot may fall behind before stepping
        var settleTrigger: CGFloat = 3        // smaller tidy-up steps once stopped
        var stepLead: CGFloat = 0.55          // land this fraction of stepTrigger ahead of rest
        var stepDuration: Double = 0.3        // seconds per step
        var liftHeight: CGFloat = 3           // how high a foot lifts mid-step
        var tailWaveAmplitude: CGFloat = 5.5  // sideways tail swing at the tip while walking
        var overstretchFactor: CGFloat = 2.2  // step regardless of the other pair beyond this × stepTrigger
    }

    struct Foot {
        var position: CGPoint
        var stepFrom: CGPoint
        /// nil while planted; 0 ... 1 through a step.
        var stepProgress: Double?
        var lift: CGFloat = 0
        var stepCount = 0
        var isStepping: Bool { stepProgress != nil }
    }

    struct LegLayout {
        let spineIndex: Int
        let side: CGFloat        // +1 or -1
        let isFront: Bool
    }

    let config: Config
    /// Front-left, front-right, back-left, back-right.
    let layout: [LegLayout]
    private(set) var feet: [Foot]
    private(set) var tailPhase: CGFloat = 0
    private(set) var tailAmplitude: CGFloat = 0

    /// True when nothing is moving: no foot mid-step and the tail has come to rest.
    var isSettled: Bool { !feet.contains { $0.isStepping } && tailAmplitude < 0.05 }

    /// Legs that step together: 0 = front-left + back-right, 1 = front-right + back-left.
    static func pair(of leg: Int) -> Int { (leg == 0 || leg == 3) ? 0 : 1 }

    init(simulation sim: WanderSimulation, config: Config = Config()) {
        self.config = config
        let n = sim.spine.count
        let shoulder = min(max(config.frontSpineIndex ?? Int((CGFloat(n - 1) * 0.14).rounded()), 1), n - 2)
        let hip = min(max(config.backSpineIndex ?? Int((CGFloat(n - 1) * 0.40).rounded()), 1), n - 2)
        let layout = [
            LegLayout(spineIndex: shoulder, side: 1, isFront: true),
            LegLayout(spineIndex: shoulder, side: -1, isFront: true),
            LegLayout(spineIndex: hip, side: 1, isFront: false),
            LegLayout(spineIndex: hip, side: -1, isFront: false),
        ]
        self.layout = layout
        feet = layout.map { leg in
            let p = Self.restSpot(for: leg, spine: sim.spine, config: config)
            return Foot(position: p, stepFrom: p, stepProgress: nil)
        }
    }

    mutating func update(with sim: WanderSimulation, deltaTime rawDelta: Double) {
        let dt = min(max(rawDelta, 0), 0.1)
        let walking = sim.isWalking

        // 1. Move feet that are mid-step toward their landing spot.
        for i in feet.indices {
            guard let progress = feet[i].stepProgress else { continue }
            let next = min(progress + dt / config.stepDuration, 1)
            let target = landingSpot(for: i, sim: sim)
            let eased = CGFloat(next * next * (3 - 2 * next))          // smooth start and stop
            feet[i].position = CGPoint(x: feet[i].stepFrom.x + (target.x - feet[i].stepFrom.x) * eased,
                                       y: feet[i].stepFrom.y + (target.y - feet[i].stepFrom.y) * eased)
            feet[i].lift = config.liftHeight * CGFloat(sin(.pi * next))
            if next >= 1 {
                feet[i].stepProgress = nil
                feet[i].lift = 0
                feet[i].stepCount += 1
            } else {
                feet[i].stepProgress = next
            }
        }

        // 2. Start new steps, the foot furthest from its spot first.
        let trigger = walking ? config.stepTrigger : config.settleTrigger
        let lag = feet.indices.map { distanceFromRest($0, sim: sim) }
        for i in feet.indices.sorted(by: { lag[$0] > lag[$1] }) where !feet[i].isStepping {
            guard lag[i] > trigger else { continue }
            let otherPairInAir = feet.indices.contains { Self.pair(of: $0) != Self.pair(of: i) && feet[$0].isStepping }
            let overstretched = lag[i] > config.stepTrigger * config.overstretchFactor      // e.g. after a sharp turn
            guard !otherPairInAir || overstretched else { continue }
            startStep(i)
            // Bring the diagonal partner along if it's due soon, to keep the trot rhythm.
            if let partner = feet.indices.first(where: { $0 != i && Self.pair(of: $0) == Self.pair(of: i) }),
               !feet[partner].isStepping, lag[partner] > trigger * 0.5 {
                startStep(partner)
            }
        }

        // 3. Tail wave: swings in time with the stride, fades out when stopped.
        let targetAmplitude = walking ? config.tailWaveAmplitude : 0
        tailAmplitude += (targetAmplitude - tailAmplitude) * CGFloat(min(dt * 2, 1))
        if tailAmplitude < 0.05, !walking { tailAmplitude = 0 }
        if walking {
            let strideFrequency = sim.config.walkSpeed / sim.config.strideLength * 2 * .pi
            tailPhase = (tailPhase + strideFrequency * CGFloat(dt)).truncatingRemainder(dividingBy: 2 * .pi)
        }
    }

    // MARK: - Geometry

    /// Where a leg's shoulder or hip joint is, just inside the body edge.
    func anchor(for leg: Int, spine: [CGPoint]) -> CGPoint {
        let l = layout[leg]
        let f = PlaceholderLizardRenderer.forward(at: l.spineIndex, in: spine)
        let edge = PlaceholderLizardRenderer.halfWidth(at: l.spineIndex, of: spine.count)
        return PlaceholderLizardRenderer.offset(spine[l.spineIndex], by: CGVector(dx: -f.dy, dy: f.dx), l.side * edge * 0.6)
    }

    /// The direction an elbow or knee should point: outward, with front elbows
    /// angled back and back knees angled forward, as in a sprawling lizard.
    func bendDirection(for leg: Int, spine: [CGPoint]) -> CGVector {
        let l = layout[leg]
        let f = PlaceholderLizardRenderer.forward(at: l.spineIndex, in: spine)
        let along: CGFloat = l.isFront ? -0.5 : 0.5
        return CGVector(dx: -f.dy * l.side + f.dx * along, dy: f.dx * l.side + f.dy * along)
    }

    static func restSpot(for leg: LegLayout, spine: [CGPoint], config: Config) -> CGPoint {
        let f = PlaceholderLizardRenderer.forward(at: leg.spineIndex, in: spine)
        let edge = PlaceholderLizardRenderer.halfWidth(at: leg.spineIndex, of: spine.count)
        let lateral = (leg.isFront ? config.frontLateral : config.backLateral) ?? (edge + config.footSpread)
        let out = PlaceholderLizardRenderer.offset(spine[leg.spineIndex], by: CGVector(dx: -f.dy, dy: f.dx),
                                                    leg.side * lateral)
        return PlaceholderLizardRenderer.offset(out, by: f, leg.isFront ? config.frontReach : config.backReach)
    }

    /// Two-bone inverse kinematics: where the elbow/knee goes so the upper and
    /// lower leg reach from the anchor to the foot, bending toward `bend`.
    static func knee(anchor: CGPoint, foot: CGPoint, upper: CGFloat, lower: CGFloat, bend: CGVector) -> CGPoint {
        let dx = foot.x - anchor.x, dy = foot.y - anchor.y
        let rawDistance = hypot(dx, dy)
        let d = min(max(rawDistance, abs(upper - lower) + 0.01), upper + lower - 0.01)
        let dir = rawDistance > 0 ? CGVector(dx: dx / rawDistance, dy: dy / rawDistance) : bend
        let cosAngle = (upper * upper + d * d - lower * lower) / (2 * upper * d)
        let angle = acos(min(max(cosAngle, -1), 1))
        func rotated(_ a: CGFloat) -> CGVector {
            CGVector(dx: dir.dx * cos(a) - dir.dy * sin(a), dy: dir.dx * sin(a) + dir.dy * cos(a))
        }
        let a = rotated(angle), b = rotated(-angle)
        let pick = (a.dx * bend.dx + a.dy * bend.dy) >= (b.dx * bend.dx + b.dy * bend.dy) ? a : b
        return CGPoint(x: anchor.x + pick.dx * upper, y: anchor.y + pick.dy * upper)
    }

    // MARK: - Private

    private mutating func startStep(_ i: Int) {
        feet[i].stepFrom = feet[i].position
        feet[i].stepProgress = 0
    }

    private func distanceFromRest(_ i: Int, sim: WanderSimulation) -> CGFloat {
        WanderSimulation.distance(feet[i].position, Self.restSpot(for: layout[i], spine: sim.spine, config: config))
    }

    /// Walking feet land a little ahead of their rest spot, so they last longer before the next step.
    private func landingSpot(for i: Int, sim: WanderSimulation) -> CGPoint {
        let rest = Self.restSpot(for: layout[i], spine: sim.spine, config: config)
        guard sim.isWalking else { return rest }
        let f = PlaceholderLizardRenderer.forward(at: layout[i].spineIndex, in: sim.spine)
        return PlaceholderLizardRenderer.offset(rest, by: f, config.stepTrigger * config.stepLead)
    }
}
