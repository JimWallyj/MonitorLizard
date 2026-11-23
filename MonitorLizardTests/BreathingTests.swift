//
//  BreathingTests.swift
//  MonitorLizardTests
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct BreathingTests {

    @Test func breathesInAndOutWhileResting() {
        var breathing = Breathing(seed: 2)
        var high = false, lowAfterHigh = false
        for _ in 0..<(10 * 10) {                       // 10 s at 10 fps
            breathing.update(isResting: true, deltaTime: 0.1)
            #expect(breathing.chest >= 0 && breathing.chest <= 1)
            if breathing.chest > 0.9 { high = true }
            if high && breathing.chest < 0.1 { lowAfterHigh = true }
        }
        #expect(high && lowAfterHigh)
    }

    @Test func throatPumpsWithinFifteenSeconds() {
        var breathing = Breathing(seed: 5)
        var pumped = false
        for _ in 0..<(15 * 20) {
            breathing.update(isResting: true, deltaTime: 0.05)
            #expect(breathing.throat >= 0 && breathing.throat <= 1)
            if breathing.throat > 0.8 { pumped = true }
        }
        #expect(pumped)
    }

    @Test func settlesWhileWalking() {
        var breathing = Breathing(seed: 9)
        for _ in 0..<40 { breathing.update(isResting: true, deltaTime: 0.05) }
        for _ in 0..<20 { breathing.update(isResting: false, deltaTime: 0.05) }
        #expect(breathing.chest == 0)
        #expect(breathing.throat == 0)
        #expect(!breathing.isThroatActive)
    }
}
