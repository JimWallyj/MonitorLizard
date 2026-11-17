//
//  LizardAnimatorTests.swift
//  MonitorLizardTests
//

import Testing
@testable import MonitorLizard

struct LizardAnimatorTests {

    @Test func slowsDownWhileResting() {
        #expect(LizardAnimator.preferredFrameRate(isWalking: true) == 24)
        #expect(LizardAnimator.preferredFrameRate(isWalking: false) == 10)
    }
}
