//
//  Lizard3DViews.swift
//  MonitorLizard
//
//  Two ways of showing the 3D stand-in, to find out which one can draw with a
//  see-through background inside the habitat window:
//    • RealityView: the modern SwiftUI view.
//    • ARView: the older AppKit view, which lets us set a clear background colour.
//

import AppKit
import RealityKit
import SwiftUI

/// Picks the 3D view for the chosen renderer.
struct Lizard3DContainer: View {
    let kind: RendererKind
    let pose: LizardPose

    var body: some View {
        switch kind {
        case .arView:
            LizardARView(pose: pose)
        default:
            LizardRealityView(pose: pose)
        }
    }
}

// MARK: - RealityView

struct LizardRealityView: View {
    let pose: LizardPose
    @State private var model = Lizard3DModel()

    var body: some View {
        RealityView { content in
            content.add(model.root)
        } update: { _ in
            model.apply(pose)
        }
        .background(Color.clear)
    }
}

// MARK: - ARView

struct LizardARView: NSViewRepresentable {
    let pose: LizardPose

    final class Coordinator {
        let model = Lizard3DModel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.environment.background = .color(.clear)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(context.coordinator.model.root)
        view.scene.addAnchor(anchor)
        return view
    }

    func updateNSView(_ view: ARView, context: Context) {
        context.coordinator.model.apply(pose)
    }
}
