//
//  MonitorLizardTests.swift
//  MonitorLizardTests
//
//  Created by Jim Walejko on 11/14/26.
//

import Testing
@testable import MonitorLizard

/// Records what the controller asked the habitat to do, without opening windows.
@MainActor
final class FakeHabitat: HabitatPresenting {
    private(set) var calls: [String] = []
    func show() { calls.append("show") }
    func setPaused(_ paused: Bool) { calls.append(paused ? "pause" : "resume") }
    func hide() { calls.append("hide") }
}

@MainActor
struct LizardControllerTests {

    @Test func startsStopped() {
        let controller = LizardController(habitat: FakeHabitat())
        #expect(controller.state == .stopped)
        #expect(controller.canStart)
        #expect(!controller.canPause)
        #expect(!controller.canStop)
        #expect(controller.startTitle == "Start")
    }

    @Test func startRuns() {
        let habitat = FakeHabitat()
        let controller = LizardController(habitat: habitat)
        controller.start()
        #expect(controller.state == .running)
        #expect(!controller.canStart)
        #expect(controller.canPause)
        #expect(controller.canStop)
        #expect(habitat.calls == ["show"])
    }

    @Test func pauseThenResume() {
        let habitat = FakeHabitat()
        let controller = LizardController(habitat: habitat)
        controller.start()
        controller.pause()
        #expect(controller.state == .paused)
        #expect(controller.startTitle == "Resume")
        controller.start()
        #expect(controller.state == .running)
        #expect(habitat.calls == ["show", "pause", "resume"])
    }

    @Test func stopFromPaused() {
        let habitat = FakeHabitat()
        let controller = LizardController(habitat: habitat)
        controller.start()
        controller.pause()
        controller.stop()
        #expect(controller.state == .stopped)
        #expect(habitat.calls == ["show", "pause", "hide"])
    }

    @Test func pauseAndStopIgnoredWhenStopped() {
        let habitat = FakeHabitat()
        let controller = LizardController(habitat: habitat)
        controller.pause()
        #expect(controller.state == .stopped)
        controller.stop()
        #expect(controller.state == .stopped)
        #expect(habitat.calls.isEmpty)
    }

    @Test func restartAfterStopShowsAgain() {
        let habitat = FakeHabitat()
        let controller = LizardController(habitat: habitat)
        controller.start()
        controller.stop()
        controller.start()
        #expect(habitat.calls == ["show", "hide", "show"])
    }
}
