//
//  HabitatController.swift
//  MonitorLizard
//
//  Opens, pauses and closes the habitat window. Phase 1 uses the main
//  display only; Phase 3 adds one habitat per connected display.
//

import AppKit
import Observation
import SwiftUI

/// What LizardController needs from the habitat. A protocol so tests can use
/// a stand-in that doesn't open real windows.
protocol HabitatPresenting: AnyObject {
    func show()
    func setPaused(_ paused: Bool)
    func hide()
}

/// Shared state the habitat's SwiftUI view watches.
@Observable
final class HabitatState {
    var isPaused = false
}

final class HabitatController: HabitatPresenting {

    private let state = HabitatState()
    private var window: HabitatWindow?
    private var screenObserver: (any NSObjectProtocol)?

    func show() {
        state.isPaused = false
        if window == nil {
            window = makeWindow()
        }
        window?.orderFrontRegardless()
        observeScreenChanges()
    }

    func setPaused(_ paused: Bool) {
        state.isPaused = paused
    }

    func hide() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    // MARK: - Private

    /// The display with the menu bar.
    private var primaryScreen: NSScreen? { NSScreen.screens.first }

    private func makeWindow() -> HabitatWindow? {
        guard let screen = primaryScreen else { return nil }
        let host = NSHostingView(rootView: HabitatView(state: state))
        host.sizingOptions = []        // the window sets the size, not the SwiftUI content
        return HabitatWindow.make(for: screen, content: host)
    }

    /// Keep the habitat covering the screen when displays or resolution change.
    private func observeScreenChanges() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fitToScreen()
            }
        }
    }

    private func fitToScreen() {
        guard let window, let screen = primaryScreen else { return }
        window.setFrame(screen.frame, display: true)
    }
}
