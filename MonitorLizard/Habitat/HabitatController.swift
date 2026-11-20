//
//  HabitatController.swift
//  MonitorLizard
//
//  Opens, pauses and closes the habitat window. Phase 1 uses the main
//  display only; Phase 3 adds one habitat per connected display.
//

import AppKit

/// What LizardController needs from the habitat. A protocol so tests can use
/// a stand-in that doesn't open real windows.
protocol HabitatPresenting: AnyObject {
    func show()
    func setPaused(_ paused: Bool)
    func hide()
}

final class HabitatController: HabitatPresenting {

    private var window: HabitatWindow?
    private var animator: LizardAnimator?
    private var observers: [any NSObjectProtocol] = []

    func show() {
        if window == nil, let screen = primaryScreen {
            let content = HabitatView(frame: CGRect(origin: .zero, size: screen.frame.size))
            content.autoresizingMask = [.width, .height]
            let window = HabitatWindow.make(for: screen, content: content)
            self.window = window

            let animator = LizardAnimator(container: content, kind: currentRendererKind)
            self.animator = animator
            window.orderFrontRegardless()
            animator.setTestOptions(view: currentView, forceLook: currentForceLook,
                                    followEdges: currentFollowEdges)
            animator.setPreset(currentPreset)
            animator.start()
            startObserving()
        }
        animator?.isPaused = false
        window?.orderFrontRegardless()
    }

    func setPaused(_ paused: Bool) {
        animator?.isPaused = paused
    }

    func hide() {
        animator?.stop()
        animator = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - Private

    /// The display with the menu bar.
    private var primaryScreen: NSScreen? { NSScreen.screens.first }

    private var currentRendererKind: RendererKind {
        RendererKind(rawValue: UserDefaults.standard.string(forKey: RendererKind.storageKey) ?? "") ?? .canvas2D
    }

    private var currentView: LizardView {
        LizardView(rawValue: UserDefaults.standard.string(forKey: LizardView.storageKey) ?? "") ?? .top
    }

    private var currentPreset: PerformancePreset {
        PerformancePreset(rawValue: UserDefaults.standard.string(forKey: PerformancePreset.storageKey) ?? "") ?? .lowFPS
    }

    private var currentFollowEdges: Bool {
        UserDefaults.standard.bool(forKey: WindowScanner.followEdgesKey)
    }

    private var currentForceLook: Bool {
        UserDefaults.standard.bool(forKey: LizardView.forceLookKey)
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        // Keep covering the screen when displays or resolution change.
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        })

        // Phase 1 test switch: follow the renderer picker in the control window.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animator?.setKind(self.currentRendererKind)
                self.animator?.setTestOptions(view: self.currentView, forceLook: self.currentForceLook,
                                              followEdges: self.currentFollowEdges)
                self.animator?.setPreset(self.currentPreset)
            }
        })
    }

    private func fitToScreen() {
        guard let window, let screen = primaryScreen else { return }
        window.setFrame(screen.frame, display: true)
    }
}
