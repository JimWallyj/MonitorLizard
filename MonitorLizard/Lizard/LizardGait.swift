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
        /// Phase 3 "natural walk": feet start forward as soon as they lift (no straight-up pick).
        var naturalSwing = false
        /// How strong the body wave is (side view uses more, as it's seen at an angle).
        var waveScale: CGFloat = 1
        /// Real model (round 8): where each shoulder/hip joint sits (points from its spine point:
        /// out to the side, and forward), and how far along the ground the leg reaches from it.
        var frontRootLateral: CGFloat? = nil
        var frontRootAlong: CGFloat? = nil
        var backRootLateral: CGFloat? = nil
        var backRootAlong: CGFloat? = nil
        var frontGroundReach: CGFloat? = nil
        var backGroundReach: CGFloat? = nil
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
    /// Phase 3: the body wave's driver, −1…1. Round 3: set by the FRONT legs: each front step
    /// swings the shoulders toward that side (+1 = right), and the wave then travels from the
    /// shoulders down the body to the hips and tail (see `girdleSwing(delay:)`).
    private(set) var girdleSwing: CGFloat = 0
    private var girdleTarget: CGFloat = 0
    private var girdleLead: CGFloat = 0          // first smoothing stage, for a rounder wave
    /// 1 = full body wave; eases toward 0 during sharp turns (the wave would kick the hips
    /// and tail out the wrong way while the body curls round).
    private(set) var turnCalm: CGFloat = 1
    private var lastHeading: CGFloat?
    private var clock: Double = 0
    private var swingHistory: [(time: Double, value: CGFloat)] = []

    /// The girdle swing `delay` seconds ago (the tail repeats the hips' swing a moment later,
    /// further along it, so a wave runs down the tail).
    func girdleSwing(delay: Double) -> CGFloat {
        let t = clock - delay
        guard let first = swingHistory.first else { return girdleSwing }
        if t <= first.time { return first.value }
        for k in 1..<swingHistory.count where swingHistory[k].time >= t {
            let a = swingHistory[k - 1], b = swingHistory[k]
            let u = CGFloat((t - a.time) / max(b.time - a.time, 0.000_1))
            return a.value + (b.value - a.value) * u
        }
        return girdleSwing
    }

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
        // Diagnostics (round 12): how far the gait rests each foot from its shoulder/hip.
        if config.naturalSwing, let fl = config.frontRootLateral, let fa = config.frontRootAlong,
           let bl = config.backRootLateral, let ba = config.backRootAlong {
            for (i, lateral, along) in [(1, fl, fa), (3, bl, ba)] {
                let leg = layout[i]
                let f = PlaceholderLizardRenderer.forward(at: leg.spineIndex, in: sim.spine)
                let normal = CGVector(dx: -f.dy, dy: f.dx)
                var root = PlaceholderLizardRenderer.offset(sim.spine[leg.spineIndex], by: normal, leg.side * lateral)
                root = PlaceholderLizardRenderer.offset(root, by: f, along)
                let rest = Self.restSpot(for: leg, spine: sim.spine, config: config)
                let landing = PlaceholderLizardRenderer.offset(rest, by: f, config.stepTrigger * config.stepLead)
                let behind = PlaceholderLizardRenderer.offset(rest, by: f, -config.stepTrigger)
                print("Monitor Lizard: gait \(leg.isFront ? "front" : "back") foot: rest \(Int(WanderSimulation.distance(rest, root))) pt "
                      + "from joint, landing \(Int(WanderSimulation.distance(landing, root))) pt, "
                      + "at step time \(Int(WanderSimulation.distance(behind, root))) pt "
                      + "(reach \(Int((leg.isFront ? config.frontGroundReach : config.backGroundReach) ?? 0)) pt)")
            }
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
            let eased = config.naturalSwing
                ? CGFloat(1 - pow(1 - next, 1.7))                     // sets off forward at once, settles in
                : CGFloat(next * next * (3 - 2 * next))               // smooth start and stop
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
            // Natural walk (round 10): back to strict diagonal pairs (front-left with rear-right,
            // front-right with rear-left), but a foot that has used most of its spare reach steps
            // early, and one right at the edge of its reach may step even if the other pair is up.
            // Round 12: an early step only once the foot has gone at least 70% of a normal step
            // (otherwise the reach check fired just after landing: rapid tiny steps and shaking).
            let stretched = config.naturalSwing && walking && lag[i] > config.stepTrigger * 0.7
                && nearReachLimit(i, sim: sim, share: 0.85)
            guard lag[i] > trigger || stretched else { continue }
            let otherPairInAir = feet.indices.contains { Self.pair(of: $0) != Self.pair(of: i) && feet[$0].isStepping }
            // Round 11: in the natural walk a pair never steps while the other pair is up (breaking
            // the pairs put both front legs, or both rear legs, into step together), except in an
            // extreme case such as a very sharp turn.
            let overstretched = config.naturalSwing
                ? lag[i] > config.stepTrigger * 2.2
                : lag[i] > config.stepTrigger * config.overstretchFactor      // e.g. after a sharp turn
            guard !otherPairInAir || overstretched else { continue }
            startStep(i)
            // Bring the diagonal partner along, to keep the trot rhythm (natural walk: always).
            if let partner = feet.indices.first(where: { $0 != i && Self.pair(of: $0) == Self.pair(of: i) }),
               !feet[partner].isStepping, config.naturalSwing || lag[partner] > trigger * 0.5 {
                startStep(partner)
            }
        }

        // 3. Tail wave: swings in time with the stride, fades out when stopped.
        if let last = lastHeading, dt > 0 {
            let turnRate = abs(WanderSimulation.normalizedAngle(sim.heading - last)) / CGFloat(dt)
            let calmGoal = min(max(1 - (turnRate - 1.0) / 1.5, 0), 1)   // full wave below 1 rad/s, none above 2.5
            turnCalm += (calmGoal - turnCalm) * CGFloat(min(dt * 5, 1))
        }
        lastHeading = sim.heading

        let girdleGoal = walking ? girdleTarget : 0
        // Two smoothing stages turn the step-by-step switches into a smooth, wave-like swing.
        let rate = CGFloat(min(dt / (config.stepDuration * 0.45), 1))
        girdleLead += (girdleGoal - girdleLead) * rate
        girdleSwing += (girdleLead - girdleSwing) * rate
        if abs(girdleSwing) < 0.001, !walking { girdleSwing = 0 }
        clock += dt
        swingHistory.append((clock, girdleSwing * turnCalm))
        while swingHistory.count > 2, swingHistory[1].time < clock - 2.5 { swingHistory.removeFirst() }

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
        if layout[i].isFront { girdleTarget = layout[i].side }
        feet[i].stepFrom = feet[i].position
        feet[i].stepProgress = 0
    }

    private func distanceFromRest(_ i: Int, sim: WanderSimulation) -> CGFloat {
        WanderSimulation.distance(feet[i].position, restSpotOnSwungBody(i, sim: sim))
    }

    /// Phase 3 natural walk: the body wave's sideways offset at spine point `i` of `n`
    /// (points; + = the lizard's right). Each front step swings the shoulders; the swing
    /// travels back, reaching the hips ~0.3 s later and the tail tip ~1 s later, growing
    /// along the tail. The neck and head ride with the shoulders, less toward the snout.
    func waveOffset(at i: Int, of n: Int) -> CGFloat {
        guard config.naturalSwing, n > 3 else { return 0 }
        let walk = min(tailAmplitude / max(config.tailWaveAmplitude, 0.01), 1)
        let amount = 3.5 * walk * config.waveScale
        guard amount > 0.001 else { return 0 }
        let travel = 1.0                                   // seconds, shoulders → tail tip
        let t = CGFloat(i) / CGFloat(n - 1)
        let tF = CGFloat(layout[0].spineIndex) / CGFloat(n - 1)
        let tH = CGFloat(layout[2].spineIndex) / CGFloat(n - 1)
        if t < tF {
            return amount * (0.3 + 0.7 * t / max(tF, 0.01)) * girdleSwing * turnCalm
        }
        let u = (t - tF) / max(1 - tF, 0.01)               // 0 at the shoulders … 1 at the tail tip
        let grow = t <= tH ? 1 : 1 + 1.3 * (t - tH) / max(1 - tH, 0.01)
        return amount * grow * girdleSwing(delay: Double(u) * travel)
    }

    /// True when a planted foot has used up `share` of the leg's spare reach: the room between
    /// its rest spot and the furthest the leg can stretch (measured from the shoulder or hip on
    /// the swinging body). Round 9: measured from the rest spot, not from the shoulder/hip, so
    /// a foot at rest never counts (the round-8 version made feet step constantly).
    private func nearReachLimit(_ i: Int, sim: WanderSimulation, share: CGFloat) -> Bool {
        let leg = layout[i]
        guard let lateral = leg.isFront ? config.frontRootLateral : config.backRootLateral,
              let along = leg.isFront ? config.frontRootAlong : config.backRootAlong,
              let reach = leg.isFront ? config.frontGroundReach : config.backGroundReach else { return false }
        let k = leg.spineIndex
        let f = PlaceholderLizardRenderer.forward(at: k, in: sim.spine)
        let normal = CGVector(dx: -f.dy, dy: f.dx)
        var root = PlaceholderLizardRenderer.offset(sim.spine[k], by: normal, leg.side * lateral)
        root = PlaceholderLizardRenderer.offset(root, by: f, along)
        root = PlaceholderLizardRenderer.offset(root, by: normal, waveOffset(at: k, of: sim.spine.count))
        let restDistance = WanderSimulation.distance(restSpotOnSwungBody(i, sim: sim), root)
        let spare = max(reach - restDistance, 3)
        return WanderSimulation.distance(feet[i].position, root) > restDistance + spare * share
    }

    /// A foot's rest spot, moved sideways with the body wave at its shoulder or hip, so feet
    /// stay within reach of the swinging body (otherwise planted feet get dragged).
    private func restSpotOnSwungBody(_ i: Int, sim: WanderSimulation) -> CGPoint {
        let rest = Self.restSpot(for: layout[i], spine: sim.spine, config: config)
        let w = waveOffset(at: layout[i].spineIndex, of: sim.spine.count)
        guard w != 0 else { return rest }
        let f = PlaceholderLizardRenderer.forward(at: layout[i].spineIndex, in: sim.spine)
        return PlaceholderLizardRenderer.offset(rest, by: CGVector(dx: -f.dy, dy: f.dx), w)
    }

    /// Walking feet land a little ahead of their rest spot, so they last longer before the next step.
    private func landingSpot(for i: Int, sim: WanderSimulation) -> CGPoint {
        let rest = restSpotOnSwungBody(i, sim: sim)
        guard sim.isWalking else { return rest }
        let f = PlaceholderLizardRenderer.forward(at: layout[i].spineIndex, in: sim.spine)
        return PlaceholderLizardRenderer.offset(rest, by: f, config.stepTrigger * config.stepLead)
    }
}
