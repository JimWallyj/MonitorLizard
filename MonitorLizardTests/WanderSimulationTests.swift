//
//  WanderSimulationTests.swift
//  MonitorLizardTests
//
//  Checks the placeholder lizard's movement rules.
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct WanderSimulationTests {

    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func makeSimulation(seed: UInt64 = 42) -> WanderSimulation {
        WanderSimulation(start: CGPoint(x: 720, y: 450), heading: 0, bounds: bounds, seed: seed)
    }

    @Test func headStaysOnScreen() {
        var sim = makeSimulation()
        for _ in 0..<20_000 {          // about 5.5 minutes at 60 fps
            sim.step(by: 1.0 / 60.0, in: bounds)
            #expect(bounds.contains(sim.head))
        }
    }

    @Test func spineKeepsItsSpacing() {
        var sim = makeSimulation()
        for _ in 0..<3_000 { sim.step(by: 1.0 / 60.0, in: bounds) }
        for i in 1..<sim.spine.count {
            let gap = WanderSimulation.distance(sim.spine[i], sim.spine[i - 1])
            #expect(abs(gap - sim.config.segmentSpacing) < 0.01)
        }
    }

    @Test func sameSeedReplaysExactly() {
        var a = makeSimulation(seed: 7)
        var b = makeSimulation(seed: 7)
        for _ in 0..<1_000 {
            a.step(by: 1.0 / 60.0, in: bounds)
            b.step(by: 1.0 / 60.0, in: bounds)
        }
        #expect(a.spine == b.spine)
    }

    @Test func longGapsAreClamped() {
        var sim = makeSimulation()
        let before = sim.head
        sim.step(by: 30, in: bounds)    // e.g. resuming after a long Pause
        let moved = WanderSimulation.distance(before, sim.head)
        #expect(moved <= sim.config.walkSpeed * sim.config.maxTimeStep + 0.001)
    }

    @Test func angleNormalization() {
        #expect(abs(WanderSimulation.normalizedAngle(3 * .pi) - .pi) < 1e-9
                || abs(WanderSimulation.normalizedAngle(3 * .pi) + .pi) < 1e-9)
        #expect(abs(WanderSimulation.normalizedAngle(-0.5) + 0.5) < 1e-9)
        #expect(abs(WanderSimulation.normalizedAngle(2 * .pi + 0.25) - 0.25) < 1e-9)
    }
}
