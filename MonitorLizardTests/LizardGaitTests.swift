//
//  LizardGaitTests.swift
//  MonitorLizardTests
//
//  Checks the walking rules: planted feet stay put, diagonal pairs take
//  turns, every leg steps, feet stay near the body, and the leg IK is exact.
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct LizardGaitTests {

    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let dt = 1.0 / 24.0

    /// Runs a seeded walk, calling `check` after every tick.
    private func walk(seconds: Double, seed: UInt64 = 3,
                      check: (_ before: LizardGait, _ after: LizardGait, _ sim: WanderSimulation) -> Void) {
        var sim = WanderSimulation(start: CGPoint(x: 720, y: 450), heading: 0, bounds: bounds, seed: seed)
        var gait = LizardGait(simulation: sim)
        for _ in 0..<Int(seconds / dt) {
            let before = gait
            sim.step(by: dt, in: bounds)
            gait.update(with: sim, deltaTime: dt)
            check(before, gait, sim)
        }
    }

    @Test func plantedFeetDontSlide() {
        walk(seconds: 60) { before, after, _ in
            for i in after.feet.indices where !before.feet[i].isStepping && !after.feet[i].isStepping {
                #expect(before.feet[i].position == after.feet[i].position)
            }
        }
    }

    @Test func diagonalPairsTakeTurns() {
        var ticks = 0, bothPairsInAir = 0
        walk(seconds: 120) { _, after, _ in
            ticks += 1
            let pair0 = after.feet.indices.contains { LizardGait.pair(of: $0) == 0 && after.feet[$0].isStepping }
            let pair1 = after.feet.indices.contains { LizardGait.pair(of: $0) == 1 && after.feet[$0].isStepping }
            if pair0 && pair1 { bothPairsInAir += 1 }
        }
        // Only allowed for an overstretched leg after a sharp turn: should be rare.
        #expect(Double(bothPairsInAir) / Double(ticks) < 0.03)
    }

    @Test func everyLegSteps() {
        var final: LizardGait?
        walk(seconds: 30) { _, after, _ in final = after }
        for foot in final?.feet ?? [] {
            #expect(foot.stepCount > 5)
        }
    }

    @Test func feetStayNearTheBody() {
        walk(seconds: 60) { _, after, sim in
            for i in after.feet.indices {
                let anchor = after.anchor(for: i, spine: sim.spine)
                #expect(WanderSimulation.distance(anchor, after.feet[i].position) < 60)
            }
        }
    }

    @Test func kneeIKIsExactWhenReachable() {
        let anchor = CGPoint(x: 0, y: 0), foot = CGPoint(x: 10, y: 4)
        let knee = LizardGait.knee(anchor: anchor, foot: foot, upper: 8, lower: 7.5,
                                   bend: CGVector(dx: 0, dy: -1))
        #expect(abs(WanderSimulation.distance(anchor, knee) - 8) < 0.001)
        #expect(abs(WanderSimulation.distance(knee, foot) - 7.5) < 0.001)
        #expect(knee.y < 2)    // bent toward the requested side
    }

    @Test func realModelOverridesPlaceTheFeet() {
        let sim = WanderSimulation(start: CGPoint(x: 720, y: 450), heading: 0, bounds: bounds, seed: 1)
        var config = LizardGait.Config()
        config.frontSpineIndex = 4
        config.backSpineIndex = 9
        config.frontLateral = 14
        config.backLateral = 12
        config.frontReach = 0
        config.backReach = 0
        let gait = LizardGait(simulation: sim, config: config)
        // Heading 0 (facing right): the spine is a horizontal line, so each foot sits
        // straight above or below its spine point, at the requested distance.
        #expect(gait.layout[0].spineIndex == 4)
        #expect(gait.layout[2].spineIndex == 9)
        #expect(abs(abs(gait.feet[0].position.y - sim.spine[4].y) - 14) < 0.001)
        #expect(abs(abs(gait.feet[2].position.y - sim.spine[9].y) - 12) < 0.001)
        #expect(abs(gait.feet[0].position.x - sim.spine[4].x) < 0.001)
    }
}

struct BodyWaveTests {
    /// The body wave must swing both ways while walking (left and right), so the
    /// tail whips to both sides.
    @Test func bodyWaveSwingsBothWays() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let dt = 1.0 / 20.0
        var sim = WanderSimulation(start: CGPoint(x: 720, y: 450), heading: 0, bounds: bounds, seed: 4)
        var config = LizardGait.Config()
        config.naturalSwing = true
        var gait = LizardGait(simulation: sim, config: config)
        var most: CGFloat = 0, least: CGFloat = 0
        var delayedMost: CGFloat = 0, delayedLeast: CGFloat = 0
        for _ in 0..<Int(20 / dt) {
            sim.step(by: dt, in: bounds)
            gait.update(with: sim, deltaTime: dt)
            most = max(most, gait.girdleSwing); least = min(least, gait.girdleSwing)
            let tail = gait.girdleSwing(delay: 0.8)
            delayedMost = max(delayedMost, tail); delayedLeast = min(delayedLeast, tail)
        }
        #expect(most > 0.4 && least < -0.4)
        #expect(delayedMost > 0.4 && delayedLeast < -0.4)
    }
}
