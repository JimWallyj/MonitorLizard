//
//  Lizard3DModel.swift
//  MonitorLizard
//
//  A simple 3D stand-in lizard built from spheres and cylinders, posed every
//  frame from a LizardPose. It lies on a "floor" at z = 0, seen from above by
//  a camera on the +z axis. 1 screen point = `metersPerPoint` metres.
//

import AppKit
import RealityKit
import simd

final class Lizard3DModel {

    /// Side of the square view that renders the lizard, in points. The view
    /// follows the lizard around the screen instead of covering the screen.
    static let viewSize: CGFloat = 280
    static let metersPerPoint: Float = 0.01

    let root = Entity()
    /// The camera looking down at the lizard (used by the manual renderer).
    let camera = PerspectiveCamera()

    private var joints: [ModelEntity] = []     // spheres at spine points
    private var links: [ModelEntity] = []      // cylinders between spine points
    private var legBones: [ModelEntity] = []   // upper + lower bone per leg
    private var feet: [ModelEntity] = []
    private var eyes: [ModelEntity] = []
    private let snout: ModelEntity
    private let tongue: ModelEntity

    init(segmentCount: Int = WanderSimulation.Config().segmentCount) {
        let skin = SimpleMaterial(color: NSColor(red: 0.22, green: 0.22, blue: 0.14, alpha: 1),
                                  roughness: 0.65, isMetallic: false)
        let eyeMaterial = SimpleMaterial(color: .black, roughness: 0.2, isMetallic: false)
        let tongueMaterial = SimpleMaterial(color: NSColor(red: 0.58, green: 0.45, blue: 0.78, alpha: 1),
                                            roughness: 0.4, isMetallic: false)
        let sphere = MeshResource.generateSphere(radius: 1)
        let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)

        snout = ModelEntity(mesh: sphere, materials: [skin])
        tongue = ModelEntity(mesh: cylinder, materials: [tongueMaterial])
        root.addChild(snout)
        root.addChild(tongue)

        let container = root
        func part(_ mesh: MeshResource, _ material: SimpleMaterial) -> ModelEntity {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            container.addChild(entity)
            return entity
        }

        joints = (0..<segmentCount).map { _ in part(sphere, skin) }
        links = (0..<max(segmentCount - 1, 0)).map { _ in part(cylinder, skin) }
        legBones = (0..<8).map { _ in part(cylinder, skin) }
        feet = (0..<4).map { _ in part(sphere, skin) }
        eyes = (0..<2).map { _ in part(sphere, eyeMaterial) }

        // Camera looking straight down at the floor, framing the square view.
        let fieldOfView: Float = 20
        let visibleHeight = Float(Self.viewSize) * Self.metersPerPoint
        let distance = (visibleHeight / 2) / tan(fieldOfView / 2 * .pi / 180)
        camera.camera.fieldOfViewInDegrees = fieldOfView
        camera.camera.near = 0.1
        camera.camera.far = distance * 2
        camera.position = [0, 0, distance]
        root.addChild(camera)

        // Light from the top left, matching the 2D drop shadow.
        let light = DirectionalLight()
        light.light.intensity = 4_500
        light.look(at: .zero, from: [-3, 4, 6], relativeTo: nil)
        root.addChild(light)

        // Soft fill light from the camera's side, so the shaded side isn't black
        // when there's no environment lighting (manual renderer).
        let fill = DirectionalLight()
        fill.light.intensity = 2_200
        fill.look(at: .zero, from: [0, 0, 10], relativeTo: nil)
        root.addChild(fill)
    }

    func apply(_ pose: LizardPose) {
        let k = Self.metersPerPoint

        func world(_ p: CGPoint, z: CGFloat = 0) -> SIMD3<Float> {
            [Float(p.x) * k, -Float(p.y) * k, Float(z) * k]    // screen y points down
        }

        // Body: flattened spheres joined by cylinders.
        for (i, point) in pose.body.enumerated() where i < joints.count {
            let r = Float(point.radius) * k
            joints[i].position = world(point.center, z: point.radius * 0.6)
            joints[i].scale = [r, r, r * 0.75]
        }
        for i in links.indices where i + 1 < pose.body.count {
            let a = pose.body[i], b = pose.body[i + 1]
            place(links[i],
                  from: world(a.center, z: a.radius * 0.6),
                  to: world(b.center, z: b.radius * 0.6),
                  radius: Float(min(a.radius, b.radius)) * k,
                  flatten: 0.75)
        }

        // Legs.
        for (i, leg) in pose.legs.enumerated() where i < feet.count {
            // Elbows and knees sit up above the body's side, as in a sprawling lizard.
            let kneeHeight = 3.2 + leg.lift * 0.5
            let footHeight = 0.6 + leg.lift
            place(legBones[i * 2], from: world(leg.base, z: 2.5), to: world(leg.knee, z: kneeHeight), radius: 1.3 * k)
            place(legBones[i * 2 + 1], from: world(leg.knee, z: kneeHeight), to: world(leg.foot, z: footHeight), radius: 1.1 * k)
            feet[i].position = world(leg.foot, z: footHeight)
            feet[i].scale = SIMD3(repeating: 1.8 * k)
        }

        // Head, eyes, tongue.
        snout.position = world(pose.snoutCenter, z: 3.3)
        snout.orientation = simd_quatf(angle: -Float(pose.headAngle), axis: [0, 0, 1])
        snout.scale = [8 * k, 5 * k, 3.6 * k]
        for (i, eye) in pose.eyes.enumerated() where i < eyes.count {
            eyes[i].position = world(eye, z: 5.6)
            eyes[i].scale = SIMD3(repeating: 1.2 * k)
        }
        if let flick = pose.tongue {
            tongue.isEnabled = true
            place(tongue, from: world(flick.start, z: 3), to: world(flick.end, z: 3), radius: 0.5 * k)
        } else {
            tongue.isEnabled = false
        }
    }

    /// Stretch a unit cylinder (height 1 along y) between two points.
    private func place(_ entity: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>,
                       radius: Float, flatten: Float = 1) {
        let delta = b - a
        let length = simd_length(delta)
        guard length > 0.000_1 else {
            entity.scale = .zero
            return
        }
        entity.position = (a + b) / 2
        entity.orientation = simd_quatf(from: [0, 1, 0], to: delta / length)
        entity.scale = [radius, length, radius * flatten]
    }
}
