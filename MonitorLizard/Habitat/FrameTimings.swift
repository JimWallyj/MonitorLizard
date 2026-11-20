//
//  FrameTimings.swift
//  MonitorLizard
//
//  Phase 1 step 6 diagnostics: where each frame's time goes. Parts of the
//  frame add their durations here; LizardAnimator prints a summary to Xcode's
//  console every 5 seconds alongside the frame rates.
//
//  • simulation: wander, routes, gait and head look
//  • pose:       building the frame's body layout (and reading the pointer)
//  • rig:        posing the 37 bones (our maths)
//  • submit:     handing the frame to RealityKit (its CPU work on our thread)
//  • gpu wait:   time from handing over until the finished frame comes back
//                (mostly GPU work, done elsewhere; not on our thread)
//

import Foundation
import QuartzCore

enum FrameTimings {
    private static var totals: [String: Double] = [:]
    private static var counts: [String: Int] = [:]
    private static let order = ["simulation", "pose", "rig", "submit", "gpu wait"]
    private static let mainThreadParts: Set<String> = ["simulation", "pose", "rig", "submit"]

    /// Add `seconds` to a named part of the frame.
    static func add(_ name: String, _ seconds: Double) {
        totals[name, default: 0] += seconds
        counts[name, default: 0] += 1
    }

    /// Average milliseconds per call for each part, and the share of one CPU core
    /// our main-thread parts used over `elapsed` seconds. Resets the totals.
    static func report(over elapsed: Double) -> String {
        guard elapsed > 0, !totals.isEmpty else { return "Monitor Lizard: timings: (no frames)" }
        var parts: [String] = []
        for name in order where counts[name, default: 0] > 0 {
            parts.append(String(format: "%@ %.2f ms", name, totals[name]! / Double(counts[name]!) * 1000))
        }
        let mainThread = mainThreadParts.reduce(0) { $0 + (totals[$1] ?? 0) }
        totals.removeAll()
        counts.removeAll()
        return "Monitor Lizard: timings per frame: " + parts.joined(separator: ", ")
            + String(format: " | main thread %.1f%% of a core", mainThread / elapsed * 100)
    }
}
