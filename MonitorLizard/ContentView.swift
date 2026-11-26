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
    @AppStorage(WindowScanner.followEdgesKey) private var followEdges = false
    @AppStorage(PerformancePreset.storageKey) private var presetRaw = PerformancePreset.lowFPS.rawValue
    @AppStorage(LightingPreset.storageKey) private var lightingRaw = LightingPreset.softSky.rawValue
    @AppStorage(ShadowPreset.storageKey) private var shadowRaw = ShadowPreset.darker.rawValue
    @AppStorage(BreathingPreset.storageKey) private var breathingRaw = BreathingPreset.normal.rawValue
    @AppStorage(WanderSimulation.longRestsKey) private var longRests = false
    @AppStorage(LizardAnimator.naturalWalkKey) private var naturalWalk = true
    @AppStorage(LizardAnimator.halfSpeedKey) private var halfSpeed = false

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
            Toggle("Follow window edges (test)", isOn: $followEdges)

            Picker("Performance (test)", selection: $presetRaw) {
                ForEach(PerformancePreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            Picker("Lighting (test)", selection: $lightingRaw) {
                ForEach(LightingPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            Picker("Shadow (test)", selection: $shadowRaw) {
                ForEach(ShadowPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            Toggle("Long rests (test)", isOn: $longRests)
            Toggle("Natural walk (test)", isOn: $naturalWalk)
            Toggle("Half speed (test)", isOn: $halfSpeed)

            Picker("Breathing (test)", selection: $breathingRaw) {
                ForEach(BreathingPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(24)
        .frame(width: 340)
    }
}

#Preview {
    ContentView()
        .environment(LizardController())
}
