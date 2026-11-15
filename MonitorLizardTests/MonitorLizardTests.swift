//
//  MonitorLizardTests.swift
//  MonitorLizardTests
//
//  Created by Jim Walejko on 11/14/26.
//

import Testing
@testable import MonitorLizard

@MainActor
struct LizardControllerTests {

    @Test func startsStopped() {
        let controller = LizardController()
        #expect(controller.state == .stopped)
        #expect(controller.canStart)
        #expect(!controller.canPause)
        #expect(!controller.canStop)
        #expect(controller.startTitle == "Start")
    }

    @Test func startRuns() {
        let controller = LizardController()
        controller.start()
        #expect(controller.state == .running)
        #expect(!controller.canStart)
        #expect(controller.canPause)
        #expect(controller.canStop)
    }

    @Test func pauseThenResume() {
        let controller = LizardController()
        controller.start()
        controller.pause()
        #expect(controller.state == .paused)
        #expect(controller.startTitle == "Resume")
        controller.start()
        #expect(controller.state == .running)
    }

    @Test func stopFromPaused() {
        let controller = LizardController()
        controller.start()
        controller.pause()
        controller.stop()
        #expect(controller.state == .stopped)
    }

    @Test func pauseAndStopIgnoredWhenStopped() {
        let controller = LizardController()
        controller.pause()
        #expect(controller.state == .stopped)
        controller.stop()
        #expect(controller.state == .stopped)
    }
}
