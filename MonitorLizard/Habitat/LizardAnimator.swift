//
//  LizardAnimator.swift
//  MonitorLizard
//
//  The lizard's frame clock. A display link ticks at up to 24 frames a
//  second while walking and 10 while resting; each tick steps the
//  simulation, moves the small lizard view to follow it, and poses the
//  lizard. SwiftUI is not involved per frame.
//

import AppKit
import QuartzCore

final class LizardAnimator: NSObject {

    nonisolated static let walkingFrameRate: Float = 24
    nonisolated static let restingFrameRate: Float = 10

    /// Frame rate to ask for, given what the lizard is doing.
    nonisolated static func preferredFrameRate(isWalking: Bool) -> Float {
        isWalking ? walkingFrameRate : restingFrameRate
    }

    private let container: NSView
    private var kind: RendererKind
    private var renderer: any LizardRendering
    private var simulation: WanderSimulation?
    private var gait: LizardGait?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var currentRate: Float = 0
    /// What was last drawn while resting, so an unchanged pose isn't redrawn.
    private var lastRestingTongueOut: Bool?

    // Diagnostics (Phase 1): how often the clock really ticks vs. how often we draw.
    private var ticksSinceReport = 0
    private var drawsSinceReport = 0
    private var lastReportTime: CFTimeInterval?

    var isPaused = false {
        didSet {
            displayLink?.isPaused = isPaused
            lastTimestamp = nil
        }
    }

    init(container: NSView, kind: RendererKind) {
        self.container = container
        self.kind = kind
        self.renderer = Self.makeRenderer(for: kind)
        super.init()
        container.addSubview(renderer.view)
    }

    func start() {
        guard displayLink == nil else { return }
        let link = container.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        setFrameRate(Self.walkingFrameRate)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        renderer.view.removeFromSuperview()
    }

    /// Switch renderer (2D / RealityView / ARView) without losing the lizard's place.
    func setKind(_ newKind: RendererKind) {
        guard newKind != kind else { return }
        renderer.view.removeFromSuperview()
        kind = newKind
        renderer = Self.makeRenderer(for: newKind)
        container.addSubview(renderer.view)
        if let simulation { place(simulation, force: true) }
    }

    // MARK: - Frame loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        reportRates(at: now)
        let bounds = container.bounds

        var sim = simulation ?? WanderSimulation(start: CGPoint(x: bounds.midX, y: bounds.midY),
                                                 heading: .random(in: -.pi ... .pi),
                                                 bounds: bounds)
        let deltaTime = lastTimestamp.map { now - $0 } ?? 0
        sim.step(by: deltaTime, in: bounds)
        lastTimestamp = now
        simulation = sim

        // The real model has its own leg positions; rebuild the gait when they change.
        let wantedConfig = renderer.gaitConfig ?? LizardGait.Config()
        var gait = (self.gait?.config == wantedConfig ? self.gait : nil)
            ?? LizardGait(simulation: sim, config: wantedConfig)
        gait.update(with: sim, deltaTime: deltaTime)
        self.gait = gait

        place(sim)
        setFrameRate(Self.preferredFrameRate(isWalking: sim.isWalking))
    }

    private func place(_ sim: WanderSimulation, force: Bool = false) {
        let center = sim.spine[sim.spine.count / 2]
        let pose = LizardPose(sim, gait: gait, relativeTo: center)

        // While resting, skip frames where nothing changed: feet settled,
        // tail still, tongue unchanged.
        let tongueOut = pose.tongue != nil
        let settled = gait?.isSettled ?? true
        if !force, !sim.isWalking, settled, lastRestingTongueOut == tongueOut { return }
        lastRestingTongueOut = sim.isWalking ? nil : tongueOut

        let half = Lizard3DModel.viewSize / 2
        renderer.view.setFrameOrigin(CGPoint(x: center.x - half, y: center.y - half))
        renderer.apply(pose, simulation: sim)
        drawsSinceReport += 1
    }

    /// Prints the real tick and draw rates to Xcode's console every 5 seconds.
    private func reportRates(at now: CFTimeInterval) {
        ticksSinceReport += 1
        guard let lastReportTime else {
            self.lastReportTime = now
            return
        }
        let elapsed = now - lastReportTime
        guard elapsed >= 5 else { return }
        let walking = simulation?.isWalking ?? true
        print(String(format: "Monitor Lizard: %.1f ticks/s, %.1f frames drawn/s (asked for %.0f, %@)",
                     Double(ticksSinceReport) / elapsed,
                     Double(drawsSinceReport) / elapsed,
                     currentRate,
                     walking ? "walking" : "resting"))
        ticksSinceReport = 0
        drawsSinceReport = 0
        self.lastReportTime = now
    }

    private func setFrameRate(_ rate: Float) {
        guard rate != currentRate, let displayLink else { return }
        currentRate = rate
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
    }

    private static func makeRenderer(for kind: RendererKind) -> any LizardRendering {
        switch kind {
        case .canvas2D:    Lizard2DRenderer()
        case .realityView: LizardRealityRenderer()
        case .arView:      LizardARRenderer()
        case .manual3D:    LizardManualRenderer()
        case .realModel:   LizardManualRenderer(scene: RealLizardModel())
        }
    }
}
