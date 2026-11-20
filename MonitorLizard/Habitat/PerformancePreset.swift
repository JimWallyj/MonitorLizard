//
//  PerformancePreset.swift
//  MonitorLizard
//
//  Phase 1 step 6 test switch: drawing resolution and walking frame rate, to
//  compare power use against how the lizard looks.
//

import CoreGraphics

nonisolated enum PerformancePreset: String, CaseIterable, Identifiable, Sendable {
    case full        // Retina (2×) resolution, 24 fps walking
    case lowRes      // standard (1×) resolution, 24 fps
    case lowFPS      // Retina, 20 fps (chosen 2026-11-19)
    case lean        // 1×, 20 fps

    static let storageKey = "performancePreset"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full:   "A: Retina, 24 fps"
        case .lowRes: "B: Standard res, 24 fps"
        case .lowFPS: "C: Retina, 20 fps – chosen"
        case .lean:   "D: Standard res, 20 fps"
        }
    }

    /// Pixels per point to draw at (capped at the screen's own scale).
    var resolutionScale: CGFloat {
        switch self {
        case .full, .lowFPS: 2
        case .lowRes, .lean: 1
        }
    }

    var walkingFrameRate: Float {
        switch self {
        case .full, .lowRes: 24
        // A 120 Hz display only runs at rates that divide 120 (24, 20, 15…); 18 came out as 20.
        case .lowFPS, .lean: 20
        }
    }
}
