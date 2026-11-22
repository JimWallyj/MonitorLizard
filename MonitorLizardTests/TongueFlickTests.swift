//
//  TongueFlickTests.swift
//  MonitorLizardTests
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct TongueFlickTests {

    @Test func flicksWithinAFewSecondsWhileResting() {
        var tongue = TongueFlick(seed: 1)
        var maxOut: CGFloat = 0
        for _ in 0..<(20 * 6) {                       // 6 s at 20 fps
            tongue.update(isWalking: false, deltaTime: 0.05)
            maxOut = max(maxOut, tongue.extent)
        }
        #expect(maxOut == 1)
    }

    @Test func staysInRangeAndGoesBackIn() {
        var tongue = TongueFlick(seed: 7)
        var sawOut = false
        var sawBackIn = false
        for _ in 0..<(20 * 30) {
            tongue.update(isWalking: false, deltaTime: 0.05)
            #expect(tongue.extent >= 0 && tongue.extent <= 1)
            #expect(tongue.shape.wave >= 0 && tongue.shape.wave <= 1)
            #expect(tongue.shape.reach >= 0.55 && tongue.shape.reach <= 1)
            if tongue.extent > 0.5 { sawOut = true }
            if sawOut && !tongue.isActive && tongue.extent == 0 { sawBackIn = true }
        }
        #expect(sawOut && sawBackIn)
    }

    @Test func eachFlickIsBrief() {
        var tongue = TongueFlick(seed: 3)
        var run = 0
        var longest = 0
        for _ in 0..<(100 * 30) {                     // 30 s at 100 Hz
            tongue.update(isWalking: true, deltaTime: 0.01)
            run = tongue.extent > 0 ? run + 1 : 0
            longest = max(longest, run)
        }
        // extend 0.25 + hold ≤ 0.8 + retract 0.3 = 1.35 s at most.
        #expect(longest > 0 && longest <= 136)
    }
}
