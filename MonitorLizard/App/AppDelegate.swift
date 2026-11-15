//
//  AppDelegate.swift
//  MonitorLizard
//
//  AppKit hooks that SwiftUI's App life cycle doesn't cover.
//  Phase 1 will create the transparent "habitat" windows from here.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Keep running when the control window is closed, so the lizard stays on
    /// screen. The menu bar item can reopen the control window at any time.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
