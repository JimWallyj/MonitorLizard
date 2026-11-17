//
//  Lizard3DViews.swift
//  MonitorLizard
//
//  The three ways of drawing the stand-in lizard (Phase 1 test switch).
//  Each provides one small square view that LizardAnimator moves around the
//  habitat, and poses the lizard inside it each frame.
//

import AppKit
import Observation
import RealityKit
import SwiftUI

protocol LizardRendering: AnyObject {
    var view: NSView { get }
    /// Leg geometry for the gait, when the renderer's lizard differs from the stand-in.
    var gaitConfig: LizardGait.Config? { get }
    func apply(_ pose: LizardPose, simulation: WanderSimulation)
}

extension LizardRendering {
    var gaitConfig: LizardGait.Config? { nil }
}

private func squareFrame() -> CGRect {
    CGRect(x: 0, y: 0, width: Lizard3DModel.viewSize, height: Lizard3DModel.viewSize)
}

// MARK: - 2D (SwiftUI Canvas, small view only)

@Observable
final class Lizard2DFrame {
    var simulation: WanderSimulation?
    var origin: CGPoint = .zero
}

struct Lizard2DView: View {
    let frame: Lizard2DFrame

    var body: some View {
        // Read the values here so SwiftUI redraws when they change.
        let simulation = frame.simulation
        let origin = frame.origin
        Canvas { context, _ in
            guard let simulation else { return }
            context.translateBy(x: -origin.x, y: -origin.y)
            PlaceholderLizardRenderer.draw(simulation, in: &context)
        }
    }
}

final class Lizard2DRenderer: LizardRendering {
    private let frame = Lizard2DFrame()
    let view: NSView

    init() {
        let host = NSHostingView(rootView: Lizard2DView(frame: frame))
        host.sizingOptions = []
        host.frame = squareFrame()
        view = host
    }

    func apply(_ pose: LizardPose, simulation: WanderSimulation) {
        let center = simulation.spine[simulation.spine.count / 2]
        let half = Lizard3DModel.viewSize / 2
        frame.origin = CGPoint(x: center.x - half, y: center.y - half)
        frame.simulation = simulation
    }
}

// MARK: - 3D with RealityView

struct LizardRealityView: View {
    let root: Entity

    var body: some View {
        RealityView { content in
            content.add(root)
        }
    }
}

final class LizardRealityRenderer: LizardRendering {
    private let model = Lizard3DModel()
    let view: NSView

    init() {
        let host = NSHostingView(rootView: LizardRealityView(root: model.root))
        host.sizingOptions = []
        host.frame = squareFrame()
        view = host
    }

    func apply(_ pose: LizardPose, simulation: WanderSimulation) {
        model.apply(pose)       // entities update directly; SwiftUI isn't involved
    }
}

// MARK: - 3D with ARView

final class LizardARRenderer: LizardRendering {
    private let model = Lizard3DModel()
    let view: NSView

    init() {
        let arView = ARView(frame: squareFrame())
        arView.environment.background = .color(.clear)
        arView.wantsLayer = true
        arView.layer?.isOpaque = false
        arView.layer?.backgroundColor = NSColor.clear.cgColor

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(model.root)
        arView.scene.addAnchor(anchor)
        view = arView
    }

    func apply(_ pose: LizardPose, simulation: WanderSimulation) {
        model.apply(pose)
    }
}
