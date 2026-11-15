//
//  ContentView.swift
//  MonitorLizard
//
//  The small control window: Start / Pause / Stop.
//

import SwiftUI

struct ContentView: View {
    @Environment(LizardController.self) private var controller

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lizard.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Monitor Lizard")
                .font(.title2.bold())

            Label(controller.state.displayName, systemImage: controller.state.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status: \(controller.state.displayName)")

            HStack(spacing: 12) {
                Button(controller.startTitle) { controller.start() }
                    .disabled(!controller.canStart)
                    .keyboardShortcut(.defaultAction)

                Button("Pause") { controller.pause() }
                    .disabled(!controller.canPause)

                Button("Stop") { controller.stop() }
                    .disabled(!controller.canStop)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 320)
    }
}

#Preview {
    ContentView()
        .environment(LizardController())
}
