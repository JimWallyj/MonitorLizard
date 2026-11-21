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

/// A 3D lizard scene the manual renderer can draw: the stand-in or the real model.
protocol LizardScene3D: AnyObject {
    var root: Entity { get }
    var camera: PerspectiveCamera { get }
    var gaitConfig: LizardGait.Config? { get }
    func apply(_ pose: LizardPose)
}

extension Lizard3DModel: LizardScene3D {
    var gaitConfig: LizardGait.Config? { nil }
}

final class LizardManualRenderer: LizardRendering {

    private let model: any LizardScene3D
    var gaitConfig: LizardGait.Config? { model.gaitConfig }
    private let renderer: RealityRenderer?
    private let metalLayer = CAMetalLayer()
    private var lastRenderTime = CACurrentMediaTime()
    private var frameInFlight = false
    private var preferredScale: CGFloat = 2
    private let shadow = ContactShadow(size: Lizard3DModel.viewSize)

    func setResolutionScale(_ scale: CGFloat) {
        preferredScale = scale
    }
    let view: NSView

    init(scene: any LizardScene3D = Lizard3DModel()) {
        model = scene
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.backgroundColor = CGColor(gray: 0, alpha: 0)

        let hostView = NSView(frame: CGRect(x: 0, y: 0,
                                            width: Lizard3DModel.viewSize,
                                            height: Lizard3DModel.viewSize))
        // Layer-hosting view: we own the layers. The soft shadow sits underneath
        // the lizard's drawing.
        let container = CALayer()
        container.frame = hostView.bounds
        metalLayer.frame = hostView.bounds
        container.addSublayer(shadow.layer)
        container.addSublayer(metalLayer)
        hostView.layer = container
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
        let start = CACurrentMediaTime()
        model.apply(pose)
        let posed = CACurrentMediaTime()
        FrameTimings.add("rig", posed - start)
        if renderFrame() {
            shadow.update(pose, liftHeight: (gaitConfig ?? LizardGait.Config()).liftHeight)
        }
        FrameTimings.add("submit", CACurrentMediaTime() - posed)
    }

    /// Returns true if a frame was submitted.
    @discardableResult
    private func renderFrame() -> Bool {
        // Skip this tick if the GPU hasn't finished the previous frame.
        guard let renderer, !frameInFlight else { return false }

        let scale = min(preferredScale, view.window?.backingScaleFactor ?? 2)
        let side = Lizard3DModel.viewSize * scale
        if metalLayer.contentsScale != scale { metalLayer.contentsScale = scale }
        if metalLayer.drawableSize.width != side {
            metalLayer.drawableSize = CGSize(width: side, height: side)
        }

        guard let drawable = metalLayer.nextDrawable() else { return false }

        let now = CACurrentMediaTime()
        let deltaTime = min(now - lastRenderTime, 0.1)
        lastRenderTime = now

        do {
            let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: drawable.texture))
            frameInFlight = true
            nonisolated(unsafe) let finishedDrawable = drawable
            let submitted = CACurrentMediaTime()
            try renderer.updateAndRender(deltaTime: deltaTime, cameraOutput: output, onComplete: { [weak self] _ in
                finishedDrawable.present()
                let finished = CACurrentMediaTime()
                Task { @MainActor in
                    self?.frameInFlight = false
                    FrameTimings.add("gpu wait", finished - submitted)
                }
            })
            return true
        } catch {
            frameInFlight = false
            print("Monitor Lizard: render failed: \(error)")
            return false
        }
    }
}
