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
    private var headLook = HeadLook()
    private var viewMode: LizardView = .top
    private var forceLook = false
    private var lastDrawnPointer: CGPoint?
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

    /// Phase 1 test switches from the control window: camera view and "look at me".
    func setTestOptions(view: LizardView, forceLook: Bool) {
        guard view != viewMode || forceLook != self.forceLook else { return }
        viewMode = view
        self.forceLook = forceLook
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
        headLook.update(isResting: !sim.isWalking, forceLook: forceLook, deltaTime: deltaTime)

        place(sim)
        setFrameRate(Self.preferredFrameRate(isWalking: sim.isWalking))
    }

    private func place(_ sim: WanderSimulation, force: Bool = false) {
        let center = sim.spine[sim.spine.count / 2]
        var pose = LizardPose(sim, gait: gait, relativeTo: center)
        pose.view = viewMode
        pose.lookAtViewer = headLook.amount
        pose.glance = headLook.glance
        let pointer = pointerLocation()
        pose.pointer = pointer.map { CGPoint(x: $0.x - center.x, y: $0.y - center.y) }

        // While looking at the pointer, redraw when the pointer moves.
        let pointerMoved: Bool = {
            guard headLook.amount > 0.01, let pointer else { return false }
            guard let last = lastDrawnPointer else { return true }
            return hypot(pointer.x - last.x, pointer.y - last.y) > 2
        }()

        // While resting, skip frames where nothing changed: feet settled,
        // tail still, head still, tongue unchanged.
        let tongueOut = pose.tongue != nil
        let settled = (gait?.isSettled ?? true) && headLook.isSettled
        if !force, !sim.isWalking, settled, !pointerMoved, lastRestingTongueOut == tongueOut { return }
        lastRestingTongueOut = sim.isWalking ? nil : tongueOut
        lastDrawnPointer = pointer

        // Side view: stay on a level "ledge" line (Phase 3 will use real ledges);
        // the wander's up/down movement becomes depth instead of floating.
        let half = Lizard3DModel.viewSize / 2
        let viewY = viewMode == .side ? container.bounds.height * 0.75 : center.y
        renderer.view.setFrameOrigin(CGPoint(x: center.x - half, y: viewY - half))
        renderer.apply(pose, simulation: sim)
        drawsSinceReport += 1
    }

    /// The mouse pointer in the habitat's coordinates (y down), or nil if unavailable.
    private func pointerLocation() -> CGPoint? {
        guard let window = container.window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return container.convert(inWindow, from: nil)
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
