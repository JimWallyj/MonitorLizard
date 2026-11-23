//
//  Breathing.swift
//  MonitorLizard
//
//  Phase 2 step 4: breathing and throat (gular) pumping while the lizard rests.
//
//  • Breathing: a slow cycle (in, out, then a pause), so a resting lizard's
//    ribs swell and relax. It fades out while walking: monitors breathe
//    poorly on the move and catch up when they stop.
//  • Gular pumping: every so often a short burst of quick throat pulses, the
//    flutter monitors make to push air into their lungs.
//
//  The renderer draws breathing-only frames at about 5 fps, and 10 fps during
//  a throat burst, so a resting lizard stays cheap.
//

import CoreGraphics
import Foundation

nonisolated enum BreathingPreset: String, CaseIterable, Identifiable, Sendable {
    case off, normal, strong, diagnostic

    static let storageKey = "breathingPreset"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:    "A: Off"
        case .normal: "B: Visible (3×)"
        case .strong: "C: Strong (4.5×)"
        case .diagnostic: "D: Diagnostic (6×)"
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .off: 0
        // Round 3 (2026-11-22): the first "natural" (1×) couldn't be seen at this size;
        // the 6× diagnostic showed the chest widening, so the method works.
        case .normal: 3
        case .strong: 4.5
        case .diagnostic: 6
        }
    }

    static var current: BreathingPreset {
        BreathingPreset(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .normal
    }
}

nonisolated struct Breathing {

    struct Config {
        var inhaleTime = 1.3                  // seconds
        var exhaleTime = 1.6
        var pauseRange = 0.6...1.8            // between breaths
        var throatInterval = 4.0...10.0       // seconds between throat bursts while resting
        var pumpsRange = 4...8                // pulses per burst
        var pumpFrequency = 2.0               // pulses per second
    }

    /// Ribs: 0 = breathed out, 1 = full breath in.
    private(set) var chest: CGFloat = 0
    /// Throat: 0 = relaxed, 1 = fully puffed.
    private(set) var throat: CGFloat = 0

    let config: Config
    private enum Phase { case inhale, exhale, pause }
    private var phase = Phase.pause
    private var timer: Double = 0.5          // time left in the current phase
    private var throatTimer: Double
    private var pumpTime: Double = 0
    private var pumpsLeft = 0
    private var rng: SeededRandom

    init(config: Config = Config(), seed: UInt64 = .random(in: .min ... .max)) {
        self.config = config
        rng = SeededRandom(seed: seed)
        throatTimer = Double.random(in: 1.0...4.0, using: &rng)
    }

    /// A throat burst is under way (draw more often).
    var isThroatActive: Bool { pumpsLeft > 0 }

    mutating func update(isResting: Bool, deltaTime rawDelta: Double) {
        let dt = min(max(rawDelta, 0), 0.1)

        guard isResting else {
            // Hold the breath while walking; ease the ribs and throat back.
            chest = max(chest - CGFloat(dt * 2), 0)
            throat = 0
            pumpsLeft = 0
            phase = .pause
            timer = 0.3
            return
        }

        // Breath cycle.
        timer -= dt
        if timer <= 0 {
            switch phase {
            case .pause:  phase = .inhale; timer = config.inhaleTime
            case .inhale: phase = .exhale; timer = config.exhaleTime
            case .exhale: phase = .pause;  timer = Double.random(in: config.pauseRange, using: &rng)
            }
        }
        switch phase {
        case .inhale:
            let u = 1 - timer / config.inhaleTime
            chest = max(chest, CGFloat(Self.smooth(u)))   // never drops while breathing in
        case .exhale:
            let u = 1 - timer / config.exhaleTime
            chest = min(chest, CGFloat(1 - Self.smooth(u)))
        case .pause:
            chest = 0
        }

        // Throat bursts.
        if pumpsLeft > 0 {
            pumpTime += dt
            let pulse = pumpTime * config.pumpFrequency
            if pulse >= Double(pumpsLeft) {
                pumpsLeft = 0
                throat = 0
                throatTimer = Double.random(in: config.throatInterval, using: &rng)
            } else {
                throat = CGFloat(0.5 - 0.5 * cos(pulse * 2 * .pi))
            }
        } else {
            throatTimer -= dt
            if throatTimer <= 0 {
                pumpsLeft = Int.random(in: config.pumpsRange, using: &rng)
                pumpTime = 0
            }
        }
    }

    private static func smooth(_ u: Double) -> Double {
        let x = min(max(u, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
