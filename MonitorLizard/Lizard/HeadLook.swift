//
//  HeadLook.swift
//  MonitorLizard
//
//  Phase 1 step 4: where the lizard looks while it rests. Sometimes it lifts
//  and turns its head to look out at you, sometimes it glances away, and it
//  faces forward again as soon as it walks. Values ease in and out smoothly.
//

import CoreGraphics
import Foundation

/// The three test views: from above, from below (on the inside of the glass), and from the side.
nonisolated enum LizardView: String, CaseIterable, Identifiable, Sendable {
    case top
    case side
    case belly

    static let storageKey = "lizardView"
    static let forceLookKey = "lizardForceLook"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top:   "Top"
        case .side:  "Side"
        case .belly: "Belly (on the glass)"
        }
    }
}

nonisolated struct HeadLook {

    /// 0 = looking ahead, 1 = looking straight at the viewer.
    private(set) var amount: CGFloat = 0
    /// Sideways glance, radians (+ = toward the lizard's left).
    private(set) var glance: CGFloat = 0

    private var target: CGFloat = 0
    private var glanceTarget: CGFloat = 0
    private var timer: Double = 0
    private var rng: SeededRandom

    init(seed: UInt64 = .random(in: .min ... .max)) {
        rng = SeededRandom(seed: seed)
    }

    /// Nothing is moving: no redraw needed while resting.
    var isSettled: Bool { amount == target && glance == glanceTarget }

    mutating func update(isResting: Bool, forceLook: Bool, deltaTime rawDelta: Double) {
        let dt = min(max(rawDelta, 0), 0.1)

        if forceLook {
            target = 1
            glanceTarget = 0
        } else if !isResting {
            target = 0
            glanceTarget = 0
            timer = 0
        } else {
            timer -= dt
            if timer <= 0 {
                // Choose what to do for the next moment of the rest.
                let roll = Double.random(in: 0..<1, using: &rng)
                if roll < 0.45 {
                    target = 1                                          // look at you
                    glanceTarget = 0
                } else if roll < 0.85 {
                    target = 0                                          // glance away to one side
                    glanceTarget = CGFloat.random(in: 0.5...0.9, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
                } else {
                    target = 0                                          // look ahead
                    glanceTarget = 0
                }
                timer = Double.random(in: 0.9...2.2, using: &rng)
            }
        }

        // Ease toward the targets (about half a second), then snap when close.
        let k = CGFloat(min(dt * 5, 1))
        amount += (target - amount) * k
        glance += (glanceTarget - glance) * k
        if abs(amount - target) < 0.005 { amount = target }
        if abs(glance - glanceTarget) < 0.005 { glance = glanceTarget }
    }
}
