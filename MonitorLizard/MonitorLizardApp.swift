//
//  MonitorLizardApp.swift
//  MonitorLizard
//
//  Created by Jim Walejko on 11/14/26.
//

import SwiftUI

@main
struct MonitorLizardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = LizardController()

    var body: some Scene {
        // The control window (a single window, not a document-style group).
        Window("Monitor Lizard", id: WindowID.control) {
            ContentView()
                .environment(controller)
        }
        .windowResizability(.contentSize)
        .commands {
            LizardCommands(controller: controller)
        }

        // Lizard icon in the macOS menu bar.
        MenuBarExtra("Monitor Lizard", systemImage: "lizard.fill") {
            MenuBarContent()
                .environment(controller)
        }
    }
}
