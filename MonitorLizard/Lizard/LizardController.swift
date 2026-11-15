//
//  LizardController.swift
//  MonitorLizard
//
//  Owns the lizard's run state. The control window, menu bar item, Lizard
//  menu and (in Phase 5) Siri all go through this one object.
//

import Foundation
import Observation

/// The lizard's overall run state.
enum LizardState: String, Sendable {
    case stopped
    case running
    case paused

    var displayName: String {
        switch self {
        case .stopped: "Stopped"
        case .running: "Running"
        case .paused:  "Paused"
        }
    }

    /// SF Symbol shown next to the state in the control window.
    var symbolName: String {
        switch self {
        case .stopped: "stop.circle.fill"
        case .running: "play.circle.fill"
        case .paused:  "pause.circle.fill"
        }
    }
}

@MainActor
@Observable
final class LizardController {

    private(set) var state: LizardState = .stopped

    var canStart: Bool { state != .running }
    var canPause: Bool { state == .running }
    var canStop:  Bool { state != .stopped }

    /// "Resume" reads better than "Start" when the lizard is only paused.
    var startTitle: String { state == .paused ? "Resume" : "Start" }

    /// Start the lizard, or resume it if paused.
    func start() {
        guard canStart else { return }
        // Phase 1: create the habitat windows (if not already open) and
        // start or resume the animation loop.
        state = .running
    }

    /// Freeze the lizard where it is; it stays visible.
    func pause() {
        guard canPause else { return }
        // Phase 1: pause the animation loop.
        state = .paused
    }

    /// Remove the lizard from the screen.
    func stop() {
        guard canStop else { return }
        // Phase 1: close the habitat windows and free rendering resources.
        state = .stopped
    }
}
