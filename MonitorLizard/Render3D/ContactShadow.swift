//
//  ContactShadow.swift
//  MonitorLizard
//
//  Phase 2 step 2: a soft shadow under the 3D lizard, drawn by Core Animation
//  from the same pose the model uses (so it costs almost nothing):
//
//  • Body shadow: the body outline, blurred and nudged down-right, away from
//    the top-left sun.
//  • Foot contacts: small dark spots under each planted foot that shrink,
//    fade and drift as the foot lifts, so the feet look pressed down.
//
//  Belly view (lizard on the inside of the glass): the shadow falls on the
//  wallpaper behind, so it's wider, fainter and further offset, with no foot
//  contacts. Side view: none for now (Phase 3 brings real ledges).
//

import AppKit
import QuartzCore

nonisolated enum ShadowPreset: String, CaseIterable, Identifiable, Sendable {
    case off, strong, darker, darkest

    static let storageKey = "shadowPreset2"   // new key: the default changed
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:     "A: Off"
        case .strong:  "B: Strong (last round's C)"
        case .darker:  "C: Darker"
        case .darkest: "D: Darkest"
        }
    }

    /// Multiplies every shadow's darkness.
    var strength: Float {
        switch self {
        case .off:     0
        case .strong:  1.6
        case .darker:  2.2
        case .darkest: 2.8
        }
    }

    static var current: ShadowPreset {
        ShadowPreset(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .darker
    }
}

final class ContactShadow {

    /// Holds both shadow layers; add it below the lizard's drawing.
    let layer = CALayer()
    private let bodyLayer = CALayer()
    private let feetLayer = CALayer()

    /// The real model's body is a little wider than the stand-in's outline.
    private let widthScale: CGFloat = 1.2

    init(size: CGFloat) {
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        for sub in [bodyLayer, feetLayer] {
            sub.frame = layer.bounds
            sub.shadowColor = .black
            layer.addSublayer(sub)
        }
        layer.actions = ["sublayers": NSNull()]
        let none: [String: any CAAction] = ["shadowPath": NSNull(), "shadowOpacity": NSNull(),
                                            "shadowRadius": NSNull(), "shadowOffset": NSNull(),
                                            "hidden": NSNull()]
        bodyLayer.actions = none
        feetLayer.actions = none
    }

    /// Side view, round 2: a soft strip lying on the ledge just behind its front edge, under
    /// the body, plus a spot under each planted foot; cut off at the ledge's ends (so it never
    /// runs on behind a window). Simple on purpose: it stays under the lizard during turns.
    private func updateOnLedge(_ pose: LizardPose, strength: Float, liftHeight: CGFloat) {
        feetLayer.isHidden = false
        let half = layer.bounds.width / 2
        let range = pose.ledgeRange ?? -half...half
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, range.lowerBound), range.upperBound) }
        let lineY = half + 1.5                              // just above the ledge's front edge (layer y-up)

        let xs = pose.body.map(\.center.x) + [pose.snoutCenter.x]
        let lo = clampX(xs.min() ?? 0), hi = clampX(xs.max() ?? 0)
        let strip = CGMutablePath()
        if hi - lo > 2 {
            strip.addRoundedRect(in: CGRect(x: half + lo, y: lineY - 1.5, width: hi - lo, height: 3),
                                 cornerWidth: 1.5, cornerHeight: 1.5)
        }
        bodyLayer.shadowPath = strip
        bodyLayer.shadowRadius = 3
        bodyLayer.shadowOffset = .zero
        bodyLayer.shadowOpacity = 0.30 * strength

        let feet = CGMutablePath()
        for leg in pose.legs {
            let up = min(max(leg.lift / max(liftHeight, 0.1), 0), 1)
            guard up < 0.8, range.contains(leg.foot.x) else { continue }
            let r = 3.5 * (1 - 0.6 * up)
            feet.addEllipse(in: CGRect(x: half + leg.foot.x - r, y: lineY - 1, width: 2 * r, height: 2))
        }
        feetLayer.shadowPath = feet
        feetLayer.shadowRadius = 2
        feetLayer.shadowOffset = .zero
        feetLayer.shadowOpacity = min(0.45 * strength, 1)
    }

    func update(_ pose: LizardPose, liftHeight: CGFloat) {
        let strength = ShadowPreset.current.strength
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard strength > 0 else {
            layer.isHidden = true
            return
        }
        layer.isHidden = false
        if pose.view == .side && pose.sideBlend > 0.5 {
            updateOnLedge(pose, strength: strength, liftHeight: liftHeight)
            return
        }
        let belly = pose.view == .belly
        // Phase 3 step 2: side view: the shadow lies on the ledge, seen at a shallow angle,
        // so it's squashed flat (by the tilt: sin 20° ≈ 0.34; a thin strip in straight profile).
        let side = pose.view == .side && pose.sideBlend > 0.5
        let squash: CGFloat = side ? (pose.naturalWalk ? 0.34 : 0.12) : 1

        // Pose points are y-down, measured from the view's centre; layers here are y-up.
        let half = layer.bounds.width / 2
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: half + p.x, y: half - p.y * squash) }
        func spot(_ c: CGPoint, _ r: CGFloat) -> CGRect {
            let ry = max(r * squash, side ? 1.2 : r)
            return CGRect(x: c.x - r, y: c.y - ry, width: 2 * r, height: 2 * ry)
        }

        // Body: overlapping circles along the spine (all drawn the same way round,
        // so they merge into one outline), plus the head.
        let body = CGMutablePath()
        for b in pose.body {
            let r = b.radius * widthScale
            let c = point(b.center)
            body.addEllipse(in: spot(c, r))
        }
        let snout = point(pose.snoutCenter)
        body.addEllipse(in: spot(snout, 6))
        bodyLayer.shadowPath = body
        bodyLayer.shadowRadius = belly ? 9 : (side ? 3 : 4)
        bodyLayer.shadowOffset = belly ? CGSize(width: 7, height: -10)
            : (side ? CGSize(width: 2, height: -1.5) : CGSize(width: 3, height: -4))
        bodyLayer.shadowOpacity = (belly ? 0.22 : 0.32) * strength

        // Feet: dark contact spots, smaller and fainter as each foot lifts.
        if belly {
            feetLayer.isHidden = true
        } else {
            feetLayer.isHidden = false
            let feet = CGMutablePath()
            for leg in pose.legs {
                let up = min(max(leg.lift / max(liftHeight, 0.1), 0), 1)
                let r = 4.5 * (1 - 0.5 * up)
                var c = point(leg.foot)
                c.x += 1.5 * up                     // drifts away from the sun as it rises
                c.y -= 2 * up * squash
                feet.addEllipse(in: spot(c, r))
            }
            feetLayer.shadowPath = feet
            feetLayer.shadowRadius = 2.5
            feetLayer.shadowOffset = CGSize(width: 1, height: -1)
            feetLayer.shadowOpacity = min(0.45 * strength, 1)
        }
    }
}
