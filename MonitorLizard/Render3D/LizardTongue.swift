//
//  LizardTongue.swift
//  MonitorLizard
//
//  Phase 2 step 3: the real lizard's forked tongue (the model has none).
//
//  Built from small shapes, measured in screen points and attached at the
//  mouth in the head's frame, so it turns with every head look:
//    shaft — a chain of short rods with round joints, so it can curve to the
//            side and up or down and carry a wave toward the tips,
//    fork  — two long tapering prongs that open and close as they wave.
//  Full length: twice the head's length, at most 36 pt; each flick reaches
//  part or all of it. The fork is the last 60% (round 4).
//

import AppKit
import RealityKit
import simd

final class LizardTongue {

    /// Place this at the mouth: +X out of the mouth, +Y the lizard's left, +Z up; units of points.
    let root = Entity()

    let length: Float                       // full length, points
    private let forkLength: Float
    private let radius: Float = 1.15
    private let segmentCount = 6
    private var joints: [Entity] = []       // each one a child of the one before
    private var rods: [Entity] = []         // scaled along X to the segment length
    private let fork = Entity()
    private let prongs: [Entity]

    init(length: Float) {
        self.length = length
        forkLength = length * 0.6

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: NSColor(srgbRed: 0.46, green: 0.26, blue: 0.40, alpha: 1))
        material.roughness = 0.3                // wet sheen
        material.specular = 0.6

        // Shapes are made along +Y; this turns +Y to +X.
        let alongX = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        let rodMesh = MeshResource.generateCylinder(height: 1, radius: radius)
        let ballMesh = MeshResource.generateSphere(radius: radius)

        var parent = root
        for index in 0..<segmentCount {
            let joint = Entity()
            if index > 0 {   // rounds off each bend (none at the mouth, where it would show early)
                joint.addChild(ModelEntity(mesh: ballMesh, materials: [material]))
            }
            let rod = Entity()
            let rodShape = ModelEntity(mesh: rodMesh, materials: [material])
            rodShape.orientation = alongX
            rodShape.position = [0.5, 0, 0]
            rod.addChild(rodShape)
            joint.addChild(rod)
            parent.addChild(joint)
            joints.append(joint)
            rods.append(rod)
            parent = joint
        }

        var prongs: [Entity] = []
        for _ in 0..<2 {
            let pivot = Entity()
            let prong = ModelEntity(mesh: .generateCone(height: forkLength, radius: radius * 0.8),
                                    materials: [material])
            prong.orientation = alongX
            prong.position = [forkLength / 2, 0, 0]
            pivot.addChild(prong)
            fork.addChild(pivot)
            prongs.append(pivot)
        }
        self.prongs = prongs
        parent.addChild(fork)
        root.isEnabled = false
    }

    func update(_ shape: TongueFlick.Shape) {
        let e = Float(min(max(shape.out, 0), 1))
        guard e > 0.01 else {
            root.isEnabled = false
            return
        }
        root.isEnabled = true

        let reach = Float(shape.reach)
        let shaftLength = e * reach * (length - forkLength)
        let segment = max(shaftLength / Float(segmentCount), 0.01)
        let n = Float(segmentCount)
        let phase = Float(shape.wavePhase)
        let wave = Float(shape.wave)

        for i in 0..<segmentCount {
            let s = (Float(i) + 0.5) / n                     // 0 at the mouth … 1 at the fork
            // The bend builds up as the tongue comes out; the wave travels toward the tips
            // and is stronger further out.
            let yaw = Float(shape.side) * e / n + wave * 0.10 * s * sin(phase - 3 * s)
            let pitch = Float(shape.up) * e / n + wave * 0.08 * s * cos(phase * 0.8 - 3 * s)
            joints[i].position = i == 0 ? .zero : [segment, 0, 0]
            joints[i].orientation = simd_quatf(angle: yaw, axis: [0, 0, 1])
                * simd_quatf(angle: -pitch, axis: [0, 1, 0])
            rods[i].scale = [segment, 1, 1]
        }

        fork.position = [segment, 0, 0]
        fork.scale = SIMD3(repeating: max(e * reach, 0.05))
        // Prongs spread about 13° each side (longer fork, round 3), scissoring and flicking up and down with the wave.
        let scissor = 0.12 * wave * sin(phase * 2)
        let flick = 0.25 * wave * sin(phase * 2 + 1)
        prongs[0].orientation = simd_quatf(angle: 0.22 + scissor, axis: [0, 0, 1])
            * simd_quatf(angle: -flick, axis: [0, 1, 0])
        prongs[1].orientation = simd_quatf(angle: -0.22 + scissor, axis: [0, 0, 1])
            * simd_quatf(angle: flick, axis: [0, 1, 0])
    }
}
