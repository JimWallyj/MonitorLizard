//
//  TongueFlick.swift
//  MonitorLizard
//
//  Phase 2 step 3: when, how far and in what shape the forked tongue is out.
//
//  A monitor "tastes" the air in short bursts of one to three flicks. Each
//  flick here gets its own reach (how far out), and its own bend to one side
//  and up or down; while out, a wave runs along the tongue toward the tips.
//  Round 2 (developer feedback): slower in and out, varied length, bending.
//

import CoreGraphics

nonisolated struct TongueFlick {

    struct Config {
        var extendTime = 0.25              // seconds to slide out
        var holdRange = 0.3...0.8          // seconds out, waving
        var retractTime = 0.3              // seconds to draw back in
        var gapBetweenFlicks = 0.2         // within a burst
        var flicksPerBurst = 1...3
        var restingInterval = 1.2...3.5    // seconds between bursts while resting
        var walkingInterval = 2.5...6.0    // and while walking
        var reachRange: ClosedRange<CGFloat> = 0.55...1.0   // fraction of full length
        var sideBend: ClosedRange<CGFloat> = -0.7...0.7     // radians along the whole tongue
        var upBend: ClosedRange<CGFloat> = -0.3...0.5
        var waveFrequency = 2.5            // waves per second while out
    }

    /// Everything the renderer needs for one frame.
    struct Shape: Equatable {
        /// 0 = in the mouth, 1 = out as far as this flick reaches.
        var out: CGFloat = 0
        /// This flick's length, as a fraction of the full tongue.
        var reach: CGFloat = 1
        /// Total bend to the lizard's left (+) or right (−), radians.
        var side: CGFloat = 0
        /// Total bend up (+) or down (−), radians.
        var up: CGFloat = 0
        /// Phase of the wave running along the tongue (radians).
        var wavePhase: CGFloat = 0
        /// Wave strength, 0…1 (grows once the tongue is out).
        var wave: CGFloat = 0
    }

    private(set) var shape = Shape()
    /// 0 = in the mouth, 1 = fully out (this flick's reach).
    var extent: CGFloat { shape.out }

    let config: Config
    private enum Phase { case idle, flicking, gap }
    private var phase = Phase.idle
    private var timer: Double              // time left in idle/gap; time elapsed while flicking
    private var hold: Double = 0.5
    private var flicksLeft = 0
    private var rng: SeededRandom

    init(config: Config = Config(), seed: UInt64 = .random(in: .min ... .max)) {
        self.config = config
        rng = SeededRandom(seed: seed)
        timer = Double.random(in: 0.5...2.0, using: &rng)
    }

    /// True while a burst is under way: the tongue needs redrawing every frame.
    var isActive: Bool { phase != .idle }

    mutating func update(isWalking: Bool, deltaTime rawDelta: Double) {
        let dt = min(max(rawDelta, 0), 0.1)
        switch phase {
        case .idle:
            timer -= dt
            if timer <= 0 {
                flicksLeft = Int.random(in: config.flicksPerBurst, using: &rng)
                startFlick()
            }
        case .gap:
            timer -= dt
            if timer <= 0 { startFlick() }
        case .flicking:
            timer += dt
            let t = timer
            let outEnd = config.extendTime
            let holdEnd = outEnd + hold
            let inEnd = holdEnd + config.retractTime
            if t < outEnd {
                let u = t / outEnd
                shape.out = CGFloat(1 - (1 - u) * (1 - u))          // quick start, easing to full
            } else if t < holdEnd {
                shape.out = 1
            } else if t < inEnd {
                let u = (t - holdEnd) / config.retractTime
                shape.out = CGFloat(1 - u * u)                      // starts gently, speeds up
            } else {
                shape.out = 0
                flicksLeft -= 1
                if flicksLeft > 0 {
                    phase = .gap
                    timer = config.gapBetweenFlicks
                } else {
                    phase = .idle
                    let range = isWalking ? config.walkingInterval : config.restingInterval
                    timer = Double.random(in: range, using: &rng)
                }
            }
            shape.wavePhase = CGFloat(t * config.waveFrequency * 2 * .pi)
            shape.wave = shape.out
        }
        if phase != .flicking { shape.wave = 0 }
    }

    private mutating func startFlick() {
        phase = .flicking
        timer = 0
        hold = Double.random(in: config.holdRange, using: &rng)
        shape.reach = CGFloat.random(in: config.reachRange, using: &rng)
        // About a third of flicks go nearly straight; the rest curve to one side.
        shape.side = Double.random(in: 0..<1, using: &rng) < 0.33
            ? CGFloat.random(in: -0.12...0.12, using: &rng)
            : CGFloat.random(in: config.sideBend, using: &rng)
        shape.up = CGFloat.random(in: config.upBend, using: &rng)
    }
}
