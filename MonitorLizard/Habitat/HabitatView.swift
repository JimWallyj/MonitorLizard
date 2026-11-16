//
//  HabitatView.swift
//  MonitorLizard
//
//  What the habitat window shows. Phase 1 step 1: the placeholder lizard,
//  redrawn up to 60 times a second while running, frozen while paused.
//

import SwiftUI

struct HabitatView: View {
    let state: HabitatState
    @State private var engine = SimulationEngine()

    var body: some View {
        let engine = engine   // local copy for the drawing closure
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: state.isPaused)) { timeline in
            Canvas { context, size in
                let simulation = engine.advance(to: timeline.date,
                                                bounds: CGRect(origin: .zero, size: size))
                PlaceholderLizardRenderer.draw(simulation, in: &context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keeps the simulation between frames. Deliberately not observable: the
/// TimelineView already drives redraws.
nonisolated final class SimulationEngine {
    private var simulation: WanderSimulation?
    private var lastDate: Date?

    func advance(to date: Date, bounds: CGRect) -> WanderSimulation {
        guard var sim = simulation else {
            let start = CGPoint(x: bounds.midX, y: bounds.midY)
            let first = WanderSimulation(start: start,
                                         heading: .random(in: -.pi ... .pi),
                                         bounds: bounds)
            simulation = first
            lastDate = date
            return first
        }
        if let lastDate {
            sim.step(by: date.timeIntervalSince(lastDate), in: bounds)
        }
        lastDate = date
        simulation = sim
        return sim
    }
}
