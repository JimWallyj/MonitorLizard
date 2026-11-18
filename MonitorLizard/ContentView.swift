//
//  ContentView.swift
//  MonitorLizard
//
//  The small control window: Start / Pause / Stop, plus (Phase 1 only) a
//  test switch for the renderer.
//

import SwiftUI

struct ContentView: View {
    @Environment(LizardController.self) private var controller
    @AppStorage(RendererKind.storageKey) private var rendererRaw = RendererKind.canvas2D.rawValue
    @AppStorage(LizardView.storageKey) private var viewRaw = LizardView.top.rawValue
    @AppStorage(LizardView.forceLookKey) private var forceLook = false

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

            Divider()

            Picker("Renderer (test)", selection: $rendererRaw) {
                ForEach(RendererKind.allCases) { kind in
                    Text(kind.displayName).tag(kind.rawValue)
                }
            }
            .pickerStyle(.menu)

            Picker("View (test)", selection: $viewRaw) {
                ForEach(LizardView.allCases) { view in
                    Text(view.displayName).tag(view.rawValue)
                }
            }
            .pickerStyle(.menu)

            Toggle("Look at me (test)", isOn: $forceLook)
        }
        .padding(24)
        .frame(width: 340)
    }
}

#Preview {
    ContentView()
        .environment(LizardController())
}
