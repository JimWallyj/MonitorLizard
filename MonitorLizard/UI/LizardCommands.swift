//
//  LizardCommands.swift
//  MonitorLizard
//
//  Menu bar menus for the app: a "Lizard" menu with Start / Pause / Stop.
//  Quit (⌘Q) is already provided in the Monitor Lizard menu by macOS.
//

import SwiftUI

struct LizardCommands: Commands {
    let controller: LizardController

    var body: some Commands {
        // The app has a single control window, so remove File > New Window.
        CommandGroup(replacing: .newItem) { }

        CommandMenu("Lizard") {
            Button(controller.startTitle) { controller.start() }
                .disabled(!controller.canStart)
            Button("Pause") { controller.pause() }
                .disabled(!controller.canPause)
            Button("Stop") { controller.stop() }
                .disabled(!controller.canStop)
        }
    }
}
