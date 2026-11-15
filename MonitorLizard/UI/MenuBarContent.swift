//
//  MenuBarContent.swift
//  MonitorLizard
//
//  The menu shown by the lizard icon in the macOS menu bar.
//

import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(LizardController.self) private var controller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Lizard: \(controller.state.displayName)")

        Divider()

        Button(controller.startTitle) { controller.start() }
            .disabled(!controller.canStart)
        Button("Pause") { controller.pause() }
            .disabled(!controller.canPause)
        Button("Stop") { controller.stop() }
            .disabled(!controller.canStop)

        Divider()

        Button("Show Control Window") {
            openWindow(id: WindowID.control)
            NSApplication.shared.activate()
        }

        Divider()

        Button("Quit Monitor Lizard") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
