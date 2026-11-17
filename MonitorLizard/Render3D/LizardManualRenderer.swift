//
//  LizardManualRenderer.swift
//  MonitorLizard
//
//  3D lizard drawn by RealityKit's RealityRenderer, frame by frame, only when
//  our LizardAnimator ticks (30 fps walking, 15 resting, none while paused).
//  RealityView and ARView redraw at the display's full refresh rate on their
//  own, which costs far more power for a slow-moving lizard.
//
//  Each frame renders into a CAMetalLayer drawable with a transparent
//  background, then presents it.
//

import AppKit
import Metal
import QuartzCore
import RealityKit

final class LizardManualRenderer: LizardRendering {

    private let model = Lizard3DModel()
    private let renderer: RealityRenderer?
    private let metalLayer = CAMetalLayer()
    private var lastRenderTime = CACurrentMediaTime()
    private var frameInFlight = false
    let view: NSView

    init() {
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.backgroundColor = CGColor(gray: 0, alpha: 0)

        let hostView = NSView(frame: CGRect(x: 0, y: 0,
                                            width: Lizard3DModel.viewSize,
                                            height: Lizard3DModel.viewSize))
        hostView.layer = metalLayer          // layer-hosting view: we own the layer
        hostView.wantsLayer = true
        view = hostView

        do {
            let renderer = try RealityRenderer()
            renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
            renderer.entities.append(model.root)
            renderer.activeCamera = model.camera
            self.renderer = renderer
        } catch {
            print("Monitor Lizard: RealityRenderer unavailable: \(error)")
            self.renderer = nil
        }
    }

    func apply(_ pose: LizardPose, simulation: WanderSimulation) {
        model.apply(pose)
        renderFrame()
    }

    private func renderFrame() {
        // Skip this tick if the GPU hasn't finished the previous frame.
        guard let renderer, !frameInFlight else { return }

        let scale = view.window?.backingScaleFactor ?? 2
        let side = Lizard3DModel.viewSize * scale
        if metalLayer.contentsScale != scale { metalLayer.contentsScale = scale }
        if metalLayer.drawableSize.width != side {
            metalLayer.drawableSize = CGSize(width: side, height: side)
        }

        guard let drawable = metalLayer.nextDrawable() else { return }

        let now = CACurrentMediaTime()
        let deltaTime = min(now - lastRenderTime, 0.1)
        lastRenderTime = now

        do {
            let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: drawable.texture))
            frameInFlight = true
            nonisolated(unsafe) let finishedDrawable = drawable
            try renderer.updateAndRender(deltaTime: deltaTime, cameraOutput: output, onComplete: { [weak self] _ in
                finishedDrawable.present()
                Task { @MainActor in self?.frameInFlight = false }
            })
        } catch {
            frameInFlight = false
            print("Monitor Lizard: render failed: \(error)")
        }
    }
}
