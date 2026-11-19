//
//  WindowEdgeTests.swift
//  MonitorLizardTests
//

import CoreGraphics
import Testing
@testable import MonitorLizard

struct WindowEdgeTests {

    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func routeRunsAlongTheWindowOutline() {
        var planner = EdgePlanner(seed: 3)
        let window = CGRect(x: 400, y: 200, width: 500, height: 350)
        for _ in 0..<50 {
            let route = planner.plan(around: window, in: screen)
            #expect(route != nil)
            guard let route else { continue }
            #expect(route.count == 2 || route.count == 3)        // one or two sides
            for p in route {
                // Every waypoint is a corner of the window grown by the offset.
                let onX = abs(p.x - (window.minX - 14)) < 0.001 || abs(p.x - (window.maxX + 14)) < 0.001
                let onY = abs(p.y - (window.minY - 14)) < 0.001 || abs(p.y - (window.maxY + 14)) < 0.001
                #expect(onX && onY)
            }
            // Consecutive corners share a side (same x or same y).
            for k in 1..<route.count {
                #expect(route[k].x == route[k - 1].x || route[k].y == route[k - 1].y)
            }
        }
    }

    @Test func noRouteForAWindowMostlyOffScreen() {
        var planner = EdgePlanner(seed: 1)
        let window = CGRect(x: -800, y: -600, width: 820, height: 610)   // only a sliver on screen
        #expect(planner.plan(around: window, in: screen) == nil)
    }

    @Test func simulationFollowsTheRouteInOrder() {
        var sim = WanderSimulation(start: CGPoint(x: 300, y: 300), heading: 0, bounds: screen, seed: 2)
        let route = [CGPoint(x: 600, y: 300), CGPoint(x: 600, y: 600), CGPoint(x: 300, y: 600)]
        sim.follow(route)
        var reached = 0
        for _ in 0..<(24 * 60) {
            let before = sim.waypoints.count
            sim.step(by: 1.0 / 24.0, in: screen)
            if sim.waypoints.count < before { reached += 1 }
            if !sim.isFollowingRoute { break }
        }
        #expect(reached == 3)
        #expect(!sim.isFollowingRoute)
    }

    @Test func distanceToRectangle() {
        let r = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(EdgePlanner.distance(from: CGPoint(x: 150, y: 150), to: r) == 0)
        #expect(EdgePlanner.distance(from: CGPoint(x: 50, y: 150), to: r) == 50)
        #expect(abs(EdgePlanner.distance(from: CGPoint(x: 70, y: 60), to: r) - 50) < 0.001)
    }
}
