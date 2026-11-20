//
//  LightingPreset.swift
//  MonitorLizard
//
//  Phase 2 step 1 test switch: how the real lizard is lit.
//
//  "Sky" light is image-based lighting from a soft, generated sky: bright
//  where the viewer is (above the desktop), warm grey at the sides, dark
//  underneath. It wraps light around the body so the shaded side keeps its
//  detail, and gives the skin a gentle sheen. The "sun" is the original
//  directional key light from the top left.
//

import CoreGraphics
import Foundation

nonisolated enum LightingPreset: String, CaseIterable, Identifiable, Sendable {
    case original    // Phase 1: key + fill directional lights, no sky
    case softSky     // sky light + a dimmer sun
    case brightSky   // brighter sky + sun
    case skyOnly     // sky light alone, no sun

    static let storageKey = "lightingPreset"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original:  "A: Original (Phase 1)"
        case .softSky:   "B: Soft sky + sun"
        case .brightSky: "C: Bright sky + sun"
        case .skyOnly:   "D: Sky only"
        }
    }

    /// Image-based light strength as a power of two (nil = no sky light).
    var skyExponent: Float? {
        switch self {
        case .original:  nil
        case .softSky:   0.5
        case .brightSky: 1.5
        case .skyOnly:   1.0
        }
    }

    /// Directional key light from the top left, in lux.
    var sunIntensity: Float {
        switch self {
        case .original:  4_500
        case .softSky:   2_500
        case .brightSky: 3_000
        case .skyOnly:   0
        }
    }

    /// Directional fill from the camera, in lux (only needed without a sky).
    var fillIntensity: Float {
        self == .original ? 2_200 : 0
    }

    static var current: LightingPreset {
        LightingPreset(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .softSky
    }
}

/// A small equirectangular sky image (+Y up): bright, slightly cool zenith,
/// warm grey horizon, dark warm ground.
nonisolated enum SkyImage {
    static func make(width: Int = 256, height: Int = 128) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let zenith: SIMD3<Float> = [1.00, 0.99, 0.96]
        let horizon: SIMD3<Float> = [0.62, 0.58, 0.52]
        let ground: SIMD3<Float> = [0.14, 0.12, 0.10]
        for row in 0..<height {
            // Memory row 0 is the top of the image = straight up.
            let elevation = Float.pi / 2 - Float.pi * (Float(row) + 0.5) / Float(height)
            let s = sin(elevation)
            let color: SIMD3<Float> = s >= 0
                ? horizon + (zenith - horizon) * pow(s, 0.6)
                : horizon + (ground - horizon) * pow(-s, 0.5)
            for column in 0..<width {
                let i = (row * width + column) * 4
                pixels[i]     = UInt8(min(255, color.x * 255))
                pixels[i + 1] = UInt8(min(255, color.y * 255))
                pixels[i + 2] = UInt8(min(255, color.z * 255))
                pixels[i + 3] = 255
            }
        }
        return context.makeImage()
    }
}
