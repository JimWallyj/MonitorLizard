//
//  HabitatWindow.swift
//  MonitorLizard
//
//  The lizard's see-through "habitat": a borderless, transparent window that
//  covers the screen just above the desktop icons and below every app window.
//  It ignores the mouse, never takes focus, and appears on every Space.
//

import AppKit

final class HabitatWindow: NSWindow {

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make(for screen: NSScreen, content: NSView) -> HabitatWindow {
        let window = HabitatWindow(contentRect: screen.frame,
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true            // every click passes through
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.contentView = content
        window.setFrame(screen.frame, display: false)
        return window
    }
}
