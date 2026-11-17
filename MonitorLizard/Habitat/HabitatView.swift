//
//  HabitatView.swift
//  MonitorLizard
//
//  The habitat window's content: a plain, see-through AppKit view whose
//  y axis points down (matching the simulation). It holds one small lizard
//  view that LizardAnimator moves around; nothing else is drawn, so the
//  rest of the screen is never repainted.
//

import AppKit

final class HabitatView: NSView {

    override var isFlipped: Bool { true }

    /// Never take part in mouse handling (the window ignores the mouse too).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
