//
//  HabitatView.swift
//  MonitorLizard
//
//  What the habitat window shows: the stand-in lizard, redrawn up to 60 times
//  a second while running, frozen while paused. Phase 1 step 2 adds a test
//  switch between the 2D drawing and two 3D renderers.
//

import SwiftUI

struct HabitatView: View {
    let state: HabitatState
    @AppStorage(RendererKind.storageKey) private var rendererRaw = RendererKind.canvas2D.rawValue
    @State private var engine = SimulationEngine()

    var body: some View {
        let engine = engine   // local copy for the drawing closures
        let kind = RendererKind(rawValue: rendererRaw) ?? .canvas2D

        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: state.isPaused)) { timeline in
                switch kind {
                case .canvas2D:
                    Canvas { context, _ in
                        let simulation = engine.advance(to: timeline.date, bounds: bounds)
                        PlaceholderLizardRenderer.draw(simulation, in: &context)
                    }
                case .realityView, .arView:
                    // A small 3D view that follows the lizard around the screen.
                    let simulation = engine.advance(to: timeline.date, bounds: bounds)
                    let center = simulation.spine[simulation.spine.count / 2]
                    Lizard3DContainer(kind: kind, pose: LizardPose(simulation, relativeTo: center))
                        .frame(width: Lizard3DModel.viewSize, height: Lizard3DModel.viewSize)
                        .position(center)
                }
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
