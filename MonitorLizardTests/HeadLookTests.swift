//
//  HeadLookTests.swift
//  MonitorLizardTests
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct HeadLookTests {

    @Test func forcedLookTurnsFullyToTheViewer() {
        var look = HeadLook(seed: 1)
        for _ in 0..<48 { look.update(isResting: false, forceLook: true, deltaTime: 1.0 / 24.0) }
        #expect(look.amount == 1)
        #expect(look.glance == 0)
        #expect(look.isSettled)
    }

    @Test func walkingFacesForwardAgain() {
        var look = HeadLook(seed: 1)
        for _ in 0..<48 { look.update(isResting: false, forceLook: true, deltaTime: 1.0 / 24.0) }
        for _ in 0..<48 { look.update(isResting: false, forceLook: false, deltaTime: 1.0 / 24.0) }
        #expect(look.amount == 0)
        #expect(look.glance == 0)
    }

    @Test func restingLooksAround() {
        var look = HeadLook(seed: 5)
        var maxAmount: Double = 0, maxGlance: Double = 0
        for _ in 0..<(24 * 30) {
            look.update(isResting: true, forceLook: false, deltaTime: 1.0 / 24.0)
            maxAmount = max(maxAmount, Double(look.amount))
            maxGlance = max(maxGlance, abs(Double(look.glance)))
        }
        #expect(maxAmount > 0.9)      // looked at the viewer at some point
        #expect(maxGlance > 0.3)      // and glanced away at some point
    }
}
