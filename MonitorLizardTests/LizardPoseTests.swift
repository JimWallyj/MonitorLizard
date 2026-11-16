//
//  LizardPoseTests.swift
//  MonitorLizardTests
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct LizardPoseTests {

    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func poseHasWholeBody() {
        let sim = WanderSimulation(start: CGPoint(x: 720, y: 450), heading: 0, bounds: bounds, seed: 1)
        let pose = LizardPose(sim, relativeTo: .zero)
        #expect(pose.body.count == sim.spine.count)
        #expect(pose.legs.count == 4)
        #expect(pose.eyes.count == 2)
    }

    @Test func poseIsRelativeToOrigin() {
        let sim = WanderSimulation(start: CGPoint(x: 720, y: 450), heading: 0, bounds: bounds, seed: 1)
        let origin = CGPoint(x: 700, y: 400)
        let pose = LizardPose(sim, relativeTo: origin)
        #expect(pose.body[0].center == CGPoint(x: sim.head.x - origin.x, y: sim.head.y - origin.y))
    }

    @Test func headPointsAlongHeading() {
        // Facing right (heading 0): the spine is laid out to the left of the head.
        let sim = WanderSimulation(start: CGPoint(x: 720, y: 450), heading: 0, bounds: bounds, seed: 1)
        let pose = LizardPose(sim, relativeTo: .zero)
        #expect(abs(pose.headAngle) < 0.001)
        #expect(pose.snoutCenter.x > pose.body[0].center.x)
    }
}
