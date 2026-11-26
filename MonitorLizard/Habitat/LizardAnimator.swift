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
    private var tongue = TongueFlick()
    /// Test switch (Phase 3): the natural side-view walk, read from UserDefaults.
    private var naturalWalk: Bool {
        UserDefaults.standard.object(forKey: Self.naturalWalkKey) as? Bool ?? true
    }
    nonisolated static let naturalWalkKey = "lizardNaturalSideWalk"
    nonisolated static let halfSpeedKey = "lizardHalfSpeed"
    private var breathing = Breathing()
    private var lastDrawTime: CFTimeInterval = 0
    private var lastDrawnBreath: CGFloat = 0
    private var lastDrawnThroat: CGFloat = 0
    private var viewMode: LizardView = .top
    private var forceLook = false
    private var lastDrawnPointer: CGPoint?

    // Step 5: following window edges.
    private var followEdges = false
    private var edgePlanner = EdgePlanner()
    private var followedWindow: ScreenWindow?
    private var lastWindowScan: CFTimeInterval = 0
    private var windows: [ScreenWindow] = []
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var currentRate: Float = 0
    private var preset: PerformancePreset = .lowFPS
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
        renderer.setResolutionScale(preset.resolutionScale)
        container.addSubview(renderer.view)
        if let simulation { place(simulation, force: true) }
    }

    /// Phase 1 test switches from the control window: camera view and "look at me".
    /// Step 6 test switch: drawing resolution and walking frame rate.
    func setPreset(_ newPreset: PerformancePreset) {
        guard newPreset != preset else { return }
        preset = newPreset
        renderer.setResolutionScale(newPreset.resolutionScale)
        if let simulation { place(simulation, force: true) }
    }

    func setTestOptions(view: LizardView, forceLook: Bool, followEdges: Bool) {
        if followEdges != self.followEdges {
            self.followEdges = followEdges
            if !followEdges {                       // switched off: drop any route
                simulation?.follow([])
                followedWindow = nil
            }
        }
        guard view != viewMode || forceLook != self.forceLook else { return }
        viewMode = view
        self.forceLook = forceLook
        if let simulation { place(simulation, force: true) }
    }

    // MARK: - Frame loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        reportRates(at: now)
        let tickStart = CACurrentMediaTime()
        let bounds = container.bounds

        var sim = simulation ?? WanderSimulation(start: CGPoint(x: bounds.midX, y: bounds.midY),
                                                 heading: .random(in: -.pi ... .pi),
                                                 bounds: bounds)
        // Test switch: "Half speed" plays the whole lizard at 50%, like slow motion.
        let timeScale = UserDefaults.standard.bool(forKey: Self.halfSpeedKey) ? 0.5 : 1.0
        let deltaTime = (lastTimestamp.map { now - $0 } ?? 0) * timeScale
        sim.levelWalking = viewMode == .side
        if viewMode == .side { if sim.laneY == nil { sim.laneY = sim.head.y } } else { sim.laneY = nil }
        if UserDefaults.standard.bool(forKey: WanderSimulation.longRestsKey) {
            sim.config.pauseChance = 1
            sim.config.pauseRange = 10...20
        } else {
            sim.config.pauseChance = WanderSimulation.Config().pauseChance
            sim.config.pauseRange = WanderSimulation.Config().pauseRange
        }
        // Natural walk, side view: tight, whipping turns (the body curls right round).
        sim.config.maxTurnRate = viewMode == .side && naturalWalk ? 3.2 : WanderSimulation.Config().maxTurnRate
        // Natural walk: the body wave does the undulating, so the path's own sashay is reduced.
        sim.config.swayAmount = naturalWalk ? 0.12 : WanderSimulation.Config().swayAmount
        sim.config.maxBend = naturalWalk ? 0.3 : nil        // ~17° per joint: no hairpin folds
        sim.step(by: deltaTime, in: bounds)
        if followEdges && viewMode != .side {
            updateEdgeRoute(&sim, now: now, bounds: bounds)
        } else if sim.isFollowingRoute || !sim.obstacles.isEmpty {
            sim.follow([])                      // edges don't apply in side view or when switched off
            sim.obstacles = []
            followedWindow = nil
        }
        lastTimestamp = now
        simulation = sim

        // The real model has its own leg positions; rebuild the gait when they change.
        var wantedConfig = renderer.gaitConfig ?? LizardGait.Config()
        wantedConfig.naturalSwing = naturalWalk
        if naturalWalk {
            // Round 10: longer steps: use nearly all the legs' room (step after ~58% of it is used
            // behind the rest spot, land ~6.5 pt ahead). The reach check stops feet being dragged.
            wantedConfig.stepTrigger *= 1.12
            wantedConfig.stepLead = 0.62
            // Round 11: quicker leg swings (0.25 s), so a pair waiting for the other pair to land
            // isn't left stretched for long.
            wantedConfig.stepDuration = 0.25
        }
        // Side view is seen at a 20° tilt, so the sideways wave shows only a third as much: boost it.
        wantedConfig.waveScale = viewMode == .side ? 1.6 : 1     // round 6: 2.2 pushed the feet out of reach
        if viewMode == .side, naturalWalk {
            // Profile walk, round 2: a prowl, not a march. Feet lift only a little more
            // than before but reach further, in fewer, slower, sweeping steps.
            wantedConfig.liftHeight *= 1.4
            wantedConfig.stepDuration = 0.32          // round 11: was 0.42
            // (Round 7's shorter side-view steps removed in round 10: the reach check now
            // keeps planted feet within reach.)
        }
        var gait = (self.gait?.config == wantedConfig ? self.gait : nil)
            ?? LizardGait(simulation: sim, config: wantedConfig)
        gait.update(with: sim, deltaTime: deltaTime)
        self.gait = gait
        headLook.update(isResting: !sim.isWalking, forceLook: forceLook, deltaTime: deltaTime)
        tongue.update(isWalking: sim.isWalking, deltaTime: deltaTime)
        breathing.update(isResting: !sim.isWalking, deltaTime: deltaTime)
        FrameTimings.add("simulation", CACurrentMediaTime() - tickStart)

        place(sim)
        // Full rate while walking or while the tongue is flicking (it's quick).
        setFrameRate(sim.isWalking || tongue.isActive ? preset.walkingFrameRate : Self.restingFrameRate)
    }

    private func place(_ sim: WanderSimulation, force: Bool = false) {
        let placeStart = CACurrentMediaTime()
        let center = sim.spine[sim.spine.count / 2]
        // Side view: measure depth from the lane line, so a lizard that has strayed off the lane
        // during a turn is drawn further back (higher) rather than the whole view drifting.
        let origin = viewMode == .side && naturalWalk ? CGPoint(x: center.x, y: sim.laneY ?? center.y) : center
        var pose = LizardPose(sim, gait: gait, relativeTo: origin)
        pose.view = viewMode
        pose.lookAtViewer = headLook.amount
        pose.glance = headLook.glance
        pose.tongueShape = tongue.shape
        pose.naturalWalk = naturalWalk
        if let gait {
            pose.liftHeight = gait.config.liftHeight
            pose.walkAmount = min(gait.tailAmplitude / max(gait.config.tailWaveAmplitude, 0.01), 1)
        }
        let breathStrength = BreathingPreset.current.multiplier
        pose.breath = breathing.chest * breathStrength
        pose.throat = breathing.throat * breathStrength
        if tongue.extent > 0 {
            // The stand-ins draw the tongue as a line from the snout.
            let f = CGVector(dx: cos(pose.headAngle), dy: sin(pose.headAngle))
            let start = PlaceholderLizardRenderer.offset(pose.snoutCenter, by: f, 8)
            pose.tongue = (start, PlaceholderLizardRenderer.offset(start, by: f, 14 * tongue.extent * tongue.shape.reach))
        } else {
            pose.tongue = nil
        }
        let pointer = pointerLocation()
        pose.pointer = pointer.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }

        // While looking at the pointer, redraw when the pointer moves.
        let pointerMoved: Bool = {
            guard headLook.amount > 0.01, let pointer else { return false }
            guard let last = lastDrawnPointer else { return true }
            return hypot(pointer.x - last.x, pointer.y - last.y) > 2
        }()

        // While resting, skip frames where nothing changed: feet settled,
        // tail still, head still, tongue unchanged.
        let tongueOut = pose.tongue != nil
        let settled = (gait?.isSettled ?? true) && headLook.isSettled && !tongue.isActive
        let now = CACurrentMediaTime()
        if !force, !sim.isWalking, settled, !pointerMoved, lastRestingTongueOut == tongueOut {
            // Only breathing is moving: draw it sparingly (about 5 fps, 10 during a throat burst).
            let breathMoved = abs(pose.breath - lastDrawnBreath) > 0.01 || abs(pose.throat - lastDrawnThroat) > 0.01
            let interval = breathing.isThroatActive ? 0.09 : 0.19
            guard breathMoved, now - lastDrawTime >= interval else { return }
        }
        lastDrawTime = now
        lastDrawnBreath = pose.breath
        lastDrawnThroat = pose.throat
        lastRestingTongueOut = sim.isWalking ? nil : tongueOut
        lastDrawnPointer = pointer

        // Side view: stay on a level "ledge" line (Phase 3 will use real ledges);
        // the wander's up/down movement becomes depth instead of floating.
        let half = Lizard3DModel.viewSize / 2
        let viewY = viewMode == .side ? container.bounds.height * 0.75 : center.y
        renderer.view.setFrameOrigin(CGPoint(x: center.x - half, y: viewY - half))
        FrameTimings.add("pose", CACurrentMediaTime() - placeStart)
        renderer.apply(pose, simulation: sim)
        drawsSinceReport += 1
    }

    /// Twice a second: check the windows, drop a route whose window moved or closed,
    /// and start a new route along the nearest window when the lizard is free.
    private func updateEdgeRoute(_ sim: inout WanderSimulation, now: CFTimeInterval, bounds: CGRect) {
        // Twice a second: re-read the windows; drop a route whose window moved or closed.
        if now - lastWindowScan >= 0.5 {
            lastWindowScan = now
            windows = WindowScanner.normalWindows().filter { $0.frame.intersects(bounds) }
            sim.obstacles = windows.map(\.frame)
            if let followed = followedWindow, sim.isFollowingRoute,
               windows.first(where: { $0.id == followed.id })?.frame != followed.frame {
                sim.follow([])
                followedWindow = nil
            }
        }

        // Every frame: when free, start the next route at the nearest window corner,
        // so it carries on around the window instead of crossing behind it.
        guard !sim.isFollowingRoute, sim.isWalking else { return }
        let head = sim.head
        let nearest = windows.sorted {
            EdgePlanner.distance(from: head, to: $0.frame) < EdgePlanner.distance(from: head, to: $1.frame)
        }
        for window in nearest.prefix(3) {
            if let route = edgePlanner.plan(around: window.frame, in: bounds, startNear: head) {
                sim.follow(route)
                followedWindow = window
                return
            }
        }
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
        print(FrameTimings.report(over: elapsed))
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
