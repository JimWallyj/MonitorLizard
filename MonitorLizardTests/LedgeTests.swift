//
//  LedgeTests.swift
//  MonitorLizardTests
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct LedgeTests {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func windowTopAndScreenBottomAreLedges() {
        let w = ScreenWindow(id: 7, frame: CGRect(x: 300, y: 300, width: 600, height: 400))
        let ledges = LedgeFinder.ledges(windows: [w], bottomY: 880, bounds: bounds)
        #expect(ledges.contains(Ledge(y: 300, xRange: 300...900, windowID: 7)))
        #expect(ledges.contains(Ledge(y: 880, xRange: 0...1440, windowID: nil)))
    }

    @Test func windowInFrontSplitsALedge() {
        let front = ScreenWindow(id: 1, frame: CGRect(x: 500, y: 200, width: 200, height: 300))
        let back = ScreenWindow(id: 2, frame: CGRect(x: 300, y: 300, width: 600, height: 400))
        let ledges = LedgeFinder.ledges(windows: [front, back], bottomY: 880, bounds: bounds)
        let backPieces = ledges.filter { $0.windowID == 2 }.map(\.xRange)
        #expect(backPieces == [300...500, 700...900])
        #expect(ledges.contains(Ledge(y: 200, xRange: 500...700, windowID: 1)))
    }

    @Test func shortPiecesAreDropped() {
        let front = ScreenWindow(id: 1, frame: CGRect(x: 400, y: 100, width: 400, height: 300))
        let back = ScreenWindow(id: 2, frame: CGRect(x: 300, y: 300, width: 600, height: 400))
        let ledges = LedgeFinder.ledges(windows: [front, back], bottomY: 880, bounds: bounds)
        // What's left of the back window's top edge: 300...400 and 800...900, both under 170 pt.
        #expect(!ledges.contains { $0.windowID == 2 })
    }

    @Test func edgesTooNearTheTopAreSkipped() {
        let w = ScreenWindow(id: 3, frame: CGRect(x: 100, y: 50, width: 600, height: 400))
        let ledges = LedgeFinder.ledges(windows: [w], bottomY: 880, bounds: bounds)
        #expect(!ledges.contains { $0.windowID == 3 })
    }

    @Test func nearestLedgePrefersTheOneBelowTheLizard() {
        let a = Ledge(y: 300, xRange: 300...900, windowID: 1)
        let b = Ledge(y: 880, xRange: 0...1440, windowID: nil)
        #expect(LedgeFinder.nearest(to: CGPoint(x: 600, y: 320), in: [a, b]) == a)
        #expect(LedgeFinder.nearest(to: CGPoint(x: 1200, y: 700), in: [a, b]) == b)
    }
}
