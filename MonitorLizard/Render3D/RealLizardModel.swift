//
//  RealLizardModel.swift
//  MonitorLizard
//
//  The real Asian water monitor (Resources/MonitorLizard.usdz, 37 bones),
//  posed every frame from the same simulation and gait as the stand-in:
//
//  • Spine, neck, head and the 18 tail bones turn to follow the body path
//    (including the tail wave), bending only sideways so the neck keeps its
//    natural rise.
//  • Each leg is solved with two-bone IK so the wrist/ankle lands exactly on
//    the gait's planted foot, with elbows and knees bending outward and up.
//
//  The model's axes are measured from its own bones at load time, so it
//  doesn't matter whether the file is Y-up or Z-up.
//

import AppKit
import RealityKit
import simd

final class RealLizardModel: LizardScene3D {

    let root = Entity()
    let camera = PerspectiveCamera()
    private(set) var gaitConfig: LizardGait.Config?

    /// Holds the lizard; moved, turned and scaled each frame.
    private let carrier = Entity()
    private var rig: RealLizardRig?

    init() {
        // Same camera as the stand-in: looking straight down, framing the 280-pt view.
        let fieldOfView: Float = 20
        let visibleHeight = Float(Lizard3DModel.viewSize) * Lizard3DModel.metersPerPoint
        let distance = (visibleHeight / 2) / tan(fieldOfView / 2 * .pi / 180)
        camera.camera.fieldOfViewInDegrees = fieldOfView
        camera.camera.near = 0.1
        camera.camera.far = distance * 2
        camera.position = [0, 0, distance]
        root.addChild(camera)

        key.look(at: .zero, from: [-3, 4, 6], relativeTo: nil)
        root.addChild(key)

        fill.look(at: .zero, from: [0, 0, 10], relativeTo: nil)
        root.addChild(fill)

        // The sky image is +Y up; turn it so its zenith faces the viewer (+Z).
        sky.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(sky)

        root.addChild(carrier)
        applyLighting(LightingPreset.current)

        Task { [weak self] in await self?.load() }
        Task { [weak self] in await self?.loadSky() }

        lightingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let preset = LightingPreset.current
                if preset != self.lighting { self.applyLighting(preset) }
            }
        }
    }

    // MARK: - Lighting

    private let key = DirectionalLight()
    private let fill = DirectionalLight()
    private let sky = Entity()
    private var skyLight: ImageBasedLightComponent?
    private var lighting: LightingPreset?
    private var lightingObserver: (any NSObjectProtocol)?

    private func loadSky() async {
        guard let image = SkyImage.make() else { return }
        do {
            let environment = try await EnvironmentResource(equirectangular: image)
            skyLight = ImageBasedLightComponent(source: .single(environment))
            carrier.components.set(ImageBasedLightReceiverComponent(imageBasedLight: sky))
            if let lighting { applyLighting(lighting) }
        } catch {
            print("Monitor Lizard: couldn't make the sky light: \(error)")
        }
    }

    private func applyLighting(_ preset: LightingPreset) {
        lighting = preset
        key.light.intensity = preset.sunIntensity
        key.isEnabled = preset.sunIntensity > 0
        fill.light.intensity = preset.fillIntensity
        fill.isEnabled = preset.fillIntensity > 0
        if let exponent = preset.skyExponent, var light = skyLight {
            light.intensityExponent = exponent
            sky.components.set(light)
        } else {
            sky.components.remove(ImageBasedLightComponent.self)
        }
        print("Monitor Lizard: lighting \(preset.displayName)")
    }

    func apply(_ pose: LizardPose) {
        rig?.apply(pose, carrier: carrier, cameraPosition: camera.position)
    }

    // MARK: - Loading

    private func load() async {
        do {
            let skinned = try await Self.loadSkinnedModel()
            skinned.removeFromParent()
            skinned.transform = .identity
            let rig = try RealLizardRig(model: skinned)
            carrier.addChild(skinned)
            carrier.isEnabled = false          // shown after the first pose
            self.rig = rig
            gaitConfig = rig.gaitConfig
            print(rig.summary)
        } catch {
            print("Monitor Lizard: couldn't load the real lizard: \(error)")
        }
    }

    private static func loadSkinnedModel() async throws -> ModelEntity {
        let scene = try await Entity(named: "MonitorLizard", in: .main)
        if let found = findSkinned(in: scene) { return found }
        throw RigError("MonitorLizard.usdz loaded, but no skinned model with joints was found in it")
    }

    private static func findSkinned(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        for child in entity.children {
            if let found = findSkinned(in: child) { return found }
        }
        return nil
    }
}

struct RigError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Rig

final class RealLizardRig {

    /// Simulation geometry the model is fitted to: the body path runs from
    /// the snout tip (11 pt ahead of spine point 0) back along 16 spine points
    /// 8 pt apart, 131 pt in all.
    static let snoutLead: Float = 11
    static let spineSpacing: Float = 8
    static let pathLength: Float = 131

    let model: ModelEntity
    let gaitConfig: LizardGait.Config
    let summary: String

    private let parents: [Int?]
    private let restLocal: [simd_float4x4]
    private let restGlobal: [simd_float4x4]
    private let order: [Int]                     // parents before children

    // Model axes (unit vectors in model space).
    private let forward: SIMD3<Float>
    private let left: SIMD3<Float>
    private let up: SIMD3<Float>
    private let modelToScene: simd_float3x3      // forward → +X, left → +Y, up → +Z
    private let pointsPerUnit: Float
    private let floorUp: Float                   // lowest point of the mesh, along `up`

    /// A bone that turns to follow the body path.
    private struct ChainBone {
        let joint: Int
        let midArc: Float            // model units from the snout tip
        let restHeading: Float       // radians, in the model's floor plane (0 = forward)
        let pointsBackward: Bool     // tail bones point away from the head
    }
    private let chain: [ChainBone]
    private let pelvis: Int
    private let pelvisArc: Float

    private struct Leg {
        let root: Int, mid: Int, end: Int
        let body: Int                // body bone the leg hangs from (Pelvis or Spine3)
        let poseIndex: Int           // which LizardPose leg drives it
        let outward: SIMD3<Float>    // knee/elbow bend direction (model space)
        let upper: Float, lower: Float
        let restEndUp: Float         // wrist/ankle height above the model's origin, along `up`
    }
    private let legs: [Leg]
    /// How far the body is lowered into a walking crouch (model units), so the
    /// legs bend and have room to stride. In the model's standing pose they're nearly straight.
    private let crouch: Float
    /// Neck and head joints, and the snout tip in the head's own frame (for the head look).
    private let neck1: Int, neck2: Int, head: Int
    private let snoutTipInHead: SIMD3<Float>
    /// Bones that swell for breathing (ribs) and throat pumping, with which of their own
    /// axes points sideways and which up, and how much they swell at full strength.
    private struct Swell {
        let joint: Int
        let sideAxis: Int, upAxis: Int
        let side: Float, up: Float
        let fromThroat: Bool
    }
    private let swells: [Swell]
    /// Tail bones from the base to the tip, and the tip's position in the last bone's frame.
    private let tailJoints: [Int]
    private let tailTipInLast: SIMD3<Float>
    /// The forked tongue, and where the mouth is in the head's frame.
    private let tongue: LizardTongue
    private let mouthInHead: simd_float4x4

    init(model: ModelEntity) throws {
        self.model = model
        let paths = model.jointNames
        let count = paths.count
        guard count > 0 else { throw RigError("model has no joints") }

        // Joint names come as paths ("Pelvis/Spine1/…"); "Thigh.L" may arrive as "Thigh_L".
        let shortNames = paths.map { ($0.split(separator: "/").last.map(String.init) ?? $0)
            .replacingOccurrences(of: ".", with: "_") }
        let indexOfPath = Dictionary(paths.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let parentList: [Int?] = paths.map { path in
            guard let slash = path.lastIndex(of: "/") else { return nil }
            return indexOfPath[String(path[..<slash])]
        }
        func index(_ name: String) throws -> Int {
            guard let i = shortNames.firstIndex(of: name) else {
                throw RigError("bone \(name) not found; bones are: \(shortNames.joined(separator: ", "))")
            }
            return i
        }

        // Rest pose, local and global.
        let restLocalList = model.jointTransforms.map { $0.matrix }
        var depth = [Int](repeating: 0, count: count)
        for i in 0..<count {
            var p = parentList[i]
            while let q = p { depth[i] += 1; p = parentList[q] }
        }
        let orderList = (0..<count).sorted { depth[$0] < depth[$1] }
        var globals = [simd_float4x4](repeating: matrix_identity_float4x4, count: count)
        for i in orderList {
            globals[i] = (parentList[i].map { globals[$0] } ?? matrix_identity_float4x4) * restLocalList[i]
        }
        parents = parentList
        restLocal = restLocalList
        order = orderList
        restGlobal = globals
        func pos(_ i: Int) -> SIMD3<Float> { let c = globals[i].columns.3; return [c.x, c.y, c.z] }

        // Axes from the bones. "Up" comes from the four feet (they stand on the ground), not
        // from the pelvis-to-head line, which slopes up because the head is held raised.
        let pelvis = try index("Pelvis")
        let head = try index("Head"), neck2 = try index("Neck2")
        let handL = try index("Hand_L"), handR = try index("Hand_R")
        let footL = try index("Foot_L"), footR = try index("Foot_R")
        let feetForward = (pos(handL) + pos(handR) - pos(footL) - pos(footR)) / 2
        let feetLeft = (pos(handL) + pos(footL) - pos(handR) - pos(footR)) / 2
        let up = simd_normalize(simd_cross(feetForward, feetLeft))
        let f0 = pos(head) - pos(pelvis)
        let forward = simd_normalize(f0 - up * simd_dot(f0, up))
        let left = simd_cross(up, forward)
        self.up = up; self.forward = forward; self.left = left
        modelToScene = simd_float3x3(rows: [forward, left, up])
        func flat(_ v: SIMD3<Float>) -> SIMD3<Float> { v - up * simd_dot(v, up) }
        func heading(_ v: SIMD3<Float>) -> Float { atan2(simd_dot(v, left), simd_dot(v, forward)) }

        // Mesh extent: floor height and snout tip.
        let bounds = model.model?.mesh.bounds ?? BoundingBox(min: pos(pelvis), max: pos(head))
        var corners: [SIMD3<Float>] = []
        for x in [bounds.min.x, bounds.max.x] { for y in [bounds.min.y, bounds.max.y] { for z in [bounds.min.z, bounds.max.z] {
            corners.append([x, y, z])
        } } }
        floorUp = corners.map { simd_dot($0, up) }.min() ?? 0
        let frontMost = corners.map { simd_dot($0, forward) }.max() ?? simd_dot(pos(head), forward)
        let headDir = simd_normalize(flat(pos(head) - pos(neck2)))
        let along = max(simd_dot(headDir, forward), 0.3)
        let tip = pos(head) + headDir * max((frontMost - simd_dot(pos(head), forward)) / along, 0)

        // Chain from the snout tip back to the tail tip, with arc lengths in the floor plane.
        var forwardChain = ["Head", "Neck2", "Neck1", "Spine3", "Spine2", "Spine1", "Pelvis"].map { try? index($0) }
            .compactMap { $0 }
        if forwardChain.count != 7 { throw RigError("spine bones missing") }
        var tailChain: [Int] = []
        for n in 1...40 {
            guard let t = try? index(String(format: "Tail%02d", n)) else { break }
            tailChain.append(t)
        }
        guard tailChain.count >= 2 else { throw RigError("tail bones missing") }
        let tailEnd = pos(tailChain[tailChain.count - 1]) * 2 - pos(tailChain[tailChain.count - 2])

        var arc: [Int: Float] = [:]
        var s = simd_length(flat(pos(head) - tip))
        arc[head] = s
        for k in 1..<forwardChain.count {
            s += simd_length(flat(pos(forwardChain[k]) - pos(forwardChain[k - 1])))
            arc[forwardChain[k]] = s
        }
        let pelvisArc = s
        var tailArc: [Float] = []
        var last = pos(pelvis)
        for t in tailChain {
            s += simd_length(flat(pos(t) - last)); last = pos(t)
            tailArc.append(s)
        }
        let tailEndArc = s + simd_length(flat(tailEnd - last))
        tailJoints = tailChain
        let tipLocal = globals[tailChain[tailChain.count - 1]].inverse * SIMD4<Float>(tailEnd, 1)
        tailTipInLast = SIMD3(tipLocal.x, tipLocal.y, tipLocal.z)
        self.pelvis = pelvis
        self.pelvisArc = pelvisArc
        self.head = head
        self.neck2 = neck2
        self.neck1 = try index("Neck1")
        let tipInHead = globals[head].inverse * SIMD4<Float>(tip, 1)
        snoutTipInHead = SIMD3(tipInHead.x, tipInHead.y, tipInHead.z)
        let ppu = Self.pathLength / tailEndArc
        pointsPerUnit = ppu

        // Tongue: out of the mouth just under the snout tip, about twice the head's length.
        let tipInHead3 = SIMD3<Float>(tipInHead.x, tipInHead.y, tipInHead.z)
        let headLength = simd_length(tipInHead3) * ppu
        let outInHead = simd_normalize(tipInHead3)
        let restHeadRotation = simd_float3x3(columns: (
            SIMD3(globals[head].columns.0.x, globals[head].columns.0.y, globals[head].columns.0.z),
            SIMD3(globals[head].columns.1.x, globals[head].columns.1.y, globals[head].columns.1.z),
            SIMD3(globals[head].columns.2.x, globals[head].columns.2.y, globals[head].columns.2.z)))
        let upGuess = restHeadRotation.inverse * up
        let upInHead = simd_normalize(upGuess - outInHead * simd_dot(upGuess, outInHead))
        let sideInHead = simd_cross(upInHead, outInHead)
        // Round 3: 2.5 pt back inside the snout and 2.5 pt up (round 4: 3.5 looked like the nose), so it leaves the mouth
        // (not the chin) in side view and stays hidden until it comes out.
        // Round 9: only 1 pt back (was 2.5), so the tongue, now angled down, leaves through the
        // front of the mouth rather than the underside of the jaw.
        let mouthBack: Float = 1.0, mouthUp: Float = 2.5
        let mouth = tipInHead3 - (outInHead * mouthBack - upInHead * mouthUp) / ppu
        let k = 1 / ppu                          // tongue is built in points
        mouthInHead = simd_float4x4(columns: (
            SIMD4(outInHead * k, 0), SIMD4(sideInHead * k, 0), SIMD4(upInHead * k, 0), SIMD4(mouth, 1)))
        // Breathing: swell bones along their own axes (scaling along a bone's own axes
        // keeps the skinning exact). Find which local axis is sideways and which is up.
        func swell(_ name: String, side: Float, up upAmount: Float, throat: Bool) throws -> Swell {
            let j = try index(name)
            let g = globals[j]
            let axes = [g.columns.0, g.columns.1, g.columns.2].map { simd_normalize(SIMD3<Float>($0.x, $0.y, $0.z)) }
            func best(_ v: SIMD3<Float>) -> Int {
                (0..<3).max { abs(simd_dot(axes[$0], v)) < abs(simd_dot(axes[$1], v)) }!
            }
            let sideAxis = best(left)
            let upAxis = (0..<3).filter { $0 != sideAxis }
                .max { abs(simd_dot(axes[$0], up)) < abs(simd_dot(axes[$1], up)) }!
            return Swell(joint: j, sideAxis: sideAxis, upAxis: upAxis, side: side, up: upAmount, fromThroat: throat)
        }
        // Round 2: about twice as wide (the body is only ~18 pt across, so 5% didn't show
        // from above), and the belly area ahead of the hips joins in.
        swells = [try swell("Spine1", side: 0.07, up: 0.03, throat: false),
                  try swell("Spine2", side: 0.11, up: 0.04, throat: false),
                  try swell("Spine3", side: 0.08, up: 0.03, throat: false),
                  try swell("Neck1", side: 0.07, up: 0.10, throat: true)]
        let axisNames = ["X", "Y", "Z"]
        print("Monitor Lizard: breathing bones " + swells.map {
            "\(shortNames[$0.joint]) side=\(axisNames[$0.sideAxis]) up=\(axisNames[$0.upAxis])"
        }.joined(separator: ", "))

        tongue = LizardTongue(length: min(2 * headLength, 36))
        model.addChild(tongue.root)
        print("Monitor Lizard: head \(Int(headLength)) pt long; tongue \(Int(min(2 * headLength, 36))) pt.")

        // Bones that follow the path. Forward bones point toward the head.
        var bones: [ChainBone] = []
        forwardChain.reverse()                                    // Pelvis … Head
        for (k, j) in forwardChain.enumerated() {
            let childPos = k + 1 < forwardChain.count ? pos(forwardChain[k + 1]) : tip
            let childArc = k + 1 < forwardChain.count ? arc[forwardChain[k + 1]]! : 0
            bones.append(ChainBone(joint: j, midArc: (arc[j]! + childArc) / 2,
                                   restHeading: heading(flat(childPos - pos(j))), pointsBackward: false))
        }
        for (k, j) in tailChain.enumerated() {
            let childPos = k + 1 < tailChain.count ? pos(tailChain[k + 1]) : tailEnd
            let childArc = k + 1 < tailChain.count ? tailArc[k + 1] : tailEndArc
            bones.append(ChainBone(joint: j, midArc: (tailArc[k] + childArc) / 2,
                                   restHeading: heading(flat(childPos - pos(j))), pointsBackward: true))
        }
        chain = bones

        // Legs. Pose leg order (from the gait): 0 front-right, 1 front-left, 2 back-right, 3 back-left.
        func makeLeg(_ a: String, _ b: String, _ c: String, poseIndex: Int, isLeft: Bool, isFront: Bool) throws -> Leg {
            let r = try index(a), m = try index(b), e = try index(c)
            let side = isLeft ? left : -left
            let outward = simd_normalize(side + up * 0.6 + forward * (isFront ? -0.3 : 0.3))
            return Leg(root: r, mid: m, end: e, body: parentList[r] ?? pelvis,
                       poseIndex: poseIndex, outward: outward,
                       upper: simd_length(pos(m) - pos(r)), lower: simd_length(pos(e) - pos(m)),
                       restEndUp: simd_dot(pos(e), up))
        }
        let legList = [
            try makeLeg("UpperArm_R", "Forearm_R", "Hand_R", poseIndex: 0, isLeft: false, isFront: true),
            try makeLeg("UpperArm_L", "Forearm_L", "Hand_L", poseIndex: 1, isLeft: true, isFront: true),
            try makeLeg("Thigh_R", "Shin_R", "Foot_R", poseIndex: 2, isLeft: false, isFront: false),
            try makeLeg("Thigh_L", "Shin_L", "Foot_L", poseIndex: 3, isLeft: true, isFront: false),
        ]
        legs = legList

        // Tell the gait where this lizard's feet naturally rest (in points).
        func legGeometry(_ rootName: String, _ endName: String) throws
            -> (index: Int, lateral: Float, reach: Float, rootLateral: Float, rootAlong: Float) {
            let r = try index(rootName), e = try index(endName)
            // Nearest body joint to the leg's root.
            let bodyJoints = forwardChain
            let near = bodyJoints.min { simd_length(flat(pos($0) - pos(r))) < simd_length(flat(pos($1) - pos(r))) }!
            let arcPoints = arc[near]! * ppu
            let spineIndex = Int(((arcPoints - Self.snoutLead) / Self.spineSpacing).rounded())
            // Round 8 fix: the spine point is up to 4 pt ahead of or behind that body joint;
            // measure from the spine point itself, so the feet rest where the legs expect them.
            let behind = arcPoints - (Self.snoutLead + Float(spineIndex) * Self.spineSpacing)
            let offset = flat(pos(e) - pos(near))
            let rootOffset = flat(pos(r) - pos(near))
            return (spineIndex, abs(simd_dot(offset, left)) * ppu, simd_dot(offset, forward) * ppu - behind,
                    abs(simd_dot(rootOffset, left)) * ppu, simd_dot(rootOffset, forward) * ppu - behind)
        }
        let fl = try legGeometry("UpperArm_L", "Hand_L"), fr = try legGeometry("UpperArm_R", "Hand_R")
        let bl = try legGeometry("Thigh_L", "Foot_L"), br = try legGeometry("Thigh_R", "Foot_R")
        var config = LizardGait.Config()
        config.frontSpineIndex = fl.index
        config.backSpineIndex = bl.index
        config.frontLateral = CGFloat((fl.lateral + fr.lateral) / 2)
        config.backLateral = CGFloat((bl.lateral + br.lateral) / 2)
        config.frontReach = CGFloat((fl.reach + fr.reach) / 2)
        config.backReach = CGFloat((bl.reach + br.reach) / 2)
        config.frontRootLateral = CGFloat((fl.rootLateral + fr.rootLateral) / 2)
        config.frontRootAlong = CGFloat((fl.rootAlong + fr.rootAlong) / 2)
        config.backRootLateral = CGFloat((bl.rootLateral + br.rootLateral) / 2)
        config.backRootAlong = CGFloat((bl.rootAlong + br.rootAlong) / 2)
        config.upperLength = CGFloat(legList[1].upper * ppu)
        config.lowerLength = CGFloat(legList[1].lower * ppu)

        // Walking crouch: lower the body by a third of the hip height.
        let hipHeights = legList.map { simd_dot(pos($0.root) - pos($0.end), up) }
        let crouch = (hipHeights.min() ?? 0) * 0.35
        self.crouch = crouch

        // Stride room (points): how far a planted foot can end up behind or ahead of
        // its rest spot before the leg would have to over-stretch.
        func strideRoom(_ leg: Leg) -> (back: Float, ahead: Float) {
            let vertical = simd_dot(pos(leg.root) - pos(leg.end), up) - crouch
            let reach = 0.95 * (leg.upper + leg.lower)
            let horizontal = sqrt(max(reach * reach - vertical * vertical, 0))
            let rest = flat(pos(leg.end) - pos(leg.root))
            let along = simd_dot(rest, forward)
            let disc = along * along - simd_length_squared(rest) + horizontal * horizontal
            guard disc > 0 else { return (0, 0) }
            return ((along + sqrt(disc)) * ppu, (-along + sqrt(disc)) * ppu)
        }
        let frontRoom = strideRoom(legList[1]), backRoom = strideRoom(legList[3])
        // How far (points, along the ground) each wrist/ankle can be from its shoulder/hip.
        func groundReach(_ leg: Leg) -> CGFloat {
            let vertical = simd_dot(pos(leg.root) - pos(leg.end), up) - crouch
            let reach = 0.97 * (leg.upper + leg.lower)
            return CGFloat(sqrt(max(reach * reach - vertical * vertical, 0)) * ppu)
        }
        config.frontGroundReach = groundReach(legList[1])
        config.backGroundReach = groundReach(legList[3])
        // Diagnostics (round 12): each leg's ground reach versus how far its foot rests from
        // its shoulder/hip in the model, in points.
        for (name, leg) in [("front", legList[1]), ("back", legList[3])] {
            let rest = simd_length(flat(pos(leg.end) - pos(leg.root))) * ppu
            print("Monitor Lizard: \(name) leg reaches \(String(format: "%.1f", Double(groundReach(leg)))) pt "
                  + "along the ground; foot rests \(String(format: "%.1f", Double(rest))) pt from the joint; "
                  + "leg \(String(format: "%.1f", Double((leg.upper + leg.lower) * ppu))) pt long")
        }
        let frontTotal = frontRoom.back + frontRoom.ahead, backTotal = backRoom.back + backRoom.ahead
        // Centre each rest spot so 60% of the room is behind it (feet travel backward while planted).
        config.frontReach += CGFloat(0.6 * frontTotal - frontRoom.back)
        config.backReach += CGFloat(0.6 * backTotal - backRoom.back)
        // Step after half the room is used; land 30% of it ahead of rest.
        let stride = max(min(frontTotal, backTotal), 6)
        config.stepTrigger = CGFloat(stride * 0.5)
        config.stepLead = 0.6
        config.settleTrigger = min(3, config.stepTrigger * 0.4)
        config.overstretchFactor = 1.3
        gaitConfig = config

        summary = """
        Monitor Lizard: real model loaded. \(count) bones; \(tailChain.count) tail bones; \
        \(String(format: "%.1f", ppu)) points per model unit.
        Monitor Lizard: front legs at spine point \(fl.index) (\(Int(config.frontLateral!)) pt out, \
        \(Int(config.frontReach)) pt reach); back legs at spine point \(bl.index) \
        (\(Int(config.backLateral!)) pt out, \(Int(config.backReach)) pt reach).
        Monitor Lizard: crouch \(String(format: "%.1f", crouch * ppu)) pt; stride room front \(Int(frontTotal)) pt, \
        back \(Int(backTotal)) pt; step after \(String(format: "%.1f", Double(config.stepTrigger))) pt.
        """
    }

    // MARK: - Posing

    func apply(_ pose: LizardPose, carrier: Entity, cameraPosition: SIMD3<Float>) {
        // Views. The lizard is posed in a "body frame" (floor = XY plane, up = +Z), then the
        // whole body frame is turned for the view: flipped for the belly view (on the glass),
        // stood on its side for the side view. Flipping mirrors left and right, so for the
        // belly view the path is mirrored first and the legs swap sides; it then walks the
        // same way on screen.
        let belly = pose.view == .belly
        let ySign: Float = belly ? 1 : -1
        let viewRotation: simd_float3x3
        switch pose.view {
        case .top:   viewRotation = matrix_identity_float3x3
        case .belly: viewRotation = simd_float3x3(simd_quatf(angle: .pi, axis: [1, 0, 0]))
        case .side:
            // Natural walk: tilted 20° so the back shows a little, as in a real three-quarter
            // view; that lets the side-to-side bend and the turns read. Otherwise straight profile.
            let tilt: Float = pose.naturalWalk ? 0.35 : 0
            viewRotation = simd_float3x3(simd_quatf(angle: -.pi / 2 + tilt, axis: [1, 0, 0]))
        }

        // 1. Body path in body-frame points (y up): snout tip, then the body centres.
        let headDirection = SIMD2<Float>(Float(cos(pose.headAngle)), ySign * Float(sin(pose.headAngle)))
        var path: [SIMD2<Float>] = pose.body.map { SIMD2(Float($0.center.x), ySign * Float($0.center.y)) }
        guard path.count >= 2 else { return }
        path.insert(path[0] + headDirection * Self.snoutLead, at: 0)
        var cumulative: [Float] = [0]
        for k in 1..<path.count { cumulative.append(cumulative[k - 1] + simd_length(path[k] - path[k - 1])) }

        func point(at s: Float) -> SIMD2<Float> {
            let s = min(max(s, 0), cumulative.last!)
            var k = 1
            while k < cumulative.count - 1 && cumulative[k] < s { k += 1 }
            let span = max(cumulative[k] - cumulative[k - 1], 0.0001)
            return path[k - 1] + (path[k] - path[k - 1]) * ((s - cumulative[k - 1]) / span)
        }
        /// Direction toward the head at arc length s, as an angle.
        func headingTowardHead(at s: Float) -> Float {
            let d = point(at: s - 3) - point(at: s + 3)
            return atan2(d.y, d.x)
        }

        // 2. Place the lizard: pelvis on the path, facing along it, feet on the floor.
        let ppu = pointsPerUnit
        let pelvisPoints = pelvisArc * ppu
        let carrierHeading = headingTowardHead(at: pelvisPoints)
        let carrierRotation = simd_float3x3(simd_quatf(angle: carrierHeading, axis: [0, 0, 1])) * modelToScene
        let scale = ppu * Lizard3DModel.metersPerPoint
        let pelvisScene = point(at: pelvisPoints) * Lizard3DModel.metersPerPoint
        let pelvisModel = position(restGlobal[pelvis])
        let offset = carrierRotation * (pelvisModel * scale)
        // Side view, natural walk: how far through a step each diagonal pair is (0 planted,
        // 1 mid-step). The body rides up a little as a pair swings over the planted ones.
        let sideWalk = pose.view == .side && pose.naturalWalk
        var swing = (a: Float(0), b: Float(0))
        if pose.naturalWalk, pose.legs.count == 4, pose.liftHeight > 0 {
            let f = pose.legs.map { Float($0.lift / pose.liftHeight) }
            swing = (max(f[0], f[3]), max(f[1], f[2]))
        }
        // Round 2 (prowl): the body sinks ~1.2 pt lower while walking (elbows and knees
        // bend more) and only glides up a little with each step.
        let bodyRise: Float = sideWalk
            ? 0.35 * max(swing.a, swing.b) - 1.2 * Float(pose.walkAmount) : 0    // points
        let carrierPosition = SIMD3<Float>(pelvisScene.x - offset.x, pelvisScene.y - offset.y,
                                           -scale * (floorUp + crouch) + bodyRise * Lizard3DModel.metersPerPoint)
        let bodyMatrix = Transform(scale: SIMD3(repeating: scale),
                                   rotation: simd_quatf(carrierRotation),
                                   translation: carrierPosition).matrix
        let viewMatrix = matrix(rotation: viewRotation, translation: .zero)
        carrier.transform = Transform(matrix: viewMatrix * bodyMatrix)

        // 3. Turn each body and tail bone to follow the path.
        var globals = restGlobal
        var yaw = [Int: Float]()
        for bone in chain {
            var desired = headingTowardHead(at: bone.midArc * ppu)
            if bone.pointsBackward { desired += .pi }
            yaw[bone.joint] = desired - (carrierHeading + bone.restHeading)
        }
        for i in order {
            let parentGlobal = parents[i].map { globals[$0] } ?? matrix_identity_float4x4
            var g = parentGlobal * restLocal[i]
            if let angle = yaw[i] {
                let turned = simd_float3x3(simd_quatf(angle: angle, axis: up)) * rotation(restGlobal[i])
                g = matrix(rotation: turned, translation: position(g))
            }
            globals[i] = g
        }

        // 3a'. Natural walk: the tail slopes down from the hips and lies along the ground.
        if pose.naturalWalk {
            let floorHeight = floorUp + crouch - bodyRise / ppu
            dropTail(toFloorAt: floorHeight, pointsPerUnit: ppu, globals: &globals)
        }

        // 3a. Side view, natural walk: head carried low and forward, nodding gently with each step.
        if pose.naturalWalk {
            let walk = Float(pose.walkAmount)
            // Round 4: the model's neck rises steeply at rest. Lower the neck ~34° but keep the
            // head level, so the top of the head lines up with the back and the snout points
            // straight ahead (a prowl). Lifting to look around comes with Phase 4.
            let headRotation = rotation(globals[head])
            raiseNeck(by: -0.6, globals: &globals)
            globals[head] = matrix(rotation: headRotation, translation: position(globals[head]))
            let nod = walk * 0.03 * (swing.a - swing.b)                  // gentle nod with each step
            if abs(nod) > 0.0005 { raiseNeck(by: nod, globals: &globals) }
        }

        // 3b. Head look: turn the neck and head toward the viewer (the camera), plus any glance.
        //     Top and belly views look toward the mouse pointer (reads clearly from above);
        //     the side view looks straight out at the viewer.
        if pose.lookAtViewer > 0.001 || abs(pose.glance) > 0.001 {
            var target: SIMD3<Float>
            if pose.view != .side, let p = pose.pointer {
                let onFloor = SIMD3<Float>(Float(p.x), ySign * Float(p.y), 0) * Lizard3DModel.metersPerPoint
                target = carrierRotation.transpose * (onFloor - carrierPosition) / scale
                // Raise the target so the head lifts a little as it turns (about 25°).
                let headPosition = position(globals[head])
                let flatDistance = simd_length((target - headPosition) - up * simd_dot(target - headPosition, up))
                target += up * (simd_dot(headPosition, up) + 0.45 * flatDistance - simd_dot(target, up))
            } else {
                let cameraInBody = viewRotation.transpose * cameraPosition
                let c = bodyMatrix.inverse * SIMD4<Float>(cameraInBody, 1)
                target = SIMD3(c.x, c.y, c.z)
            }
            lookHead(toward: target, amount: Float(pose.lookAtViewer),
                     glance: Float(pose.glance), globals: &globals)
        }

        // 4. Legs: two-bone IK onto the gait's feet.
        let inverseRotation = carrierRotation.transpose
        for leg in legs {
            let poseIndex = belly ? (leg.poseIndex ^ 1) : leg.poseIndex   // sides swap when mirrored
            guard poseIndex < pose.legs.count else { continue }
            let foot = pose.legs[poseIndex]
            let footScene = SIMD3<Float>(Float(foot.foot.x), ySign * Float(foot.foot.y), 0) * Lizard3DModel.metersPerPoint
            var target = inverseRotation * (footScene - carrierPosition) / scale
            let height = leg.restEndUp + crouch + Float(foot.lift) / ppu
            target += up * (height - simd_dot(target, up))
            // Natural walk: a lifted foot hangs loose, toes drooping toward the ground.
            let droop: Float = pose.naturalWalk && pose.liftHeight > 0
                ? 0.95 * min(max(Float(foot.lift / pose.liftHeight), 0), 1) : 0
            solveLeg(leg, target: target, footYaw: yaw[leg.body] ?? 0, droop: droop, globals: &globals)
        }

        // 4b. Tongue, at the mouth of the (possibly turned) head.
        tongue.root.transform = Transform(matrix: globals[head] * mouthInHead)
        tongue.update(pose.tongueShape)

        // 4c. Breathing: swell the ribs and throat along their own sideways and up axes.
        //     Children keep their own positions (locals are worked out from globals below).
        let breath = Float(pose.breath), throat = Float(pose.throat)
        if breath > 0.001 || throat > 0.001 {
            for s in swells {
                let amount = s.fromThroat ? throat : breath
                var d = SIMD3<Float>(repeating: 1)
                d[s.sideAxis] += s.side * amount
                d[s.upAxis] += s.up * amount
                globals[s.joint] = globals[s.joint] * simd_float4x4(diagonal: SIMD4(d, 1))
            }
        }

        // 5. Back to local transforms for RealityKit.
        var locals: [Transform] = []
        locals.reserveCapacity(globals.count)
        for i in 0..<globals.count {
            let local = (parents[i].map { globals[$0].inverse } ?? matrix_identity_float4x4) * globals[i]
            locals.append(Transform(matrix: local))
        }
        model.jointTransforms = locals
        carrier.isEnabled = true
    }

    /// Pitches Neck1 and Neck2 up by `angle` in all (60% / 40%), about each bone's own
    /// sideways axis; Neck2 and Head follow along.
    private func raiseNeck(by angle: Float, globals: inout [simd_float4x4]) {
        let localNeck2 = globals[neck1].inverse * globals[neck2]
        let localHead = globals[neck2].inverse * globals[head]
        for (joint, share) in [(neck1, Float(0.6)), (neck2, Float(0.4))] {
            let g = globals[joint]
            // This bone's sideways axis now (rest sideways turned by the bone's current yaw).
            let turn = rotation(g) * rotation(restGlobal[joint]).transpose
            let side = simd_normalize(turn * left)
            // Rotating about −left tips forward toward up (raises the head).
            let q = simd_quatf(angle: angle * share, axis: -side)
            globals[joint] = matrix(rotation: simd_float3x3(q) * rotation(g), translation: position(g))
            if joint == neck1 { globals[neck2] = globals[neck1] * localNeck2 }
            globals[head] = globals[neck2] * localHead
        }
    }

    /// Turns Neck1, Neck2 and Head (35%, 35%, 30% each) so the snout points toward `target`
    /// by `amount`, limited to about 70°, then adds a sideways glance.
    private func lookHead(toward target: SIMD3<Float>, amount: Float, glance: Float,
                          globals: inout [simd_float4x4]) {
        func snoutTip() -> SIMD3<Float> {
            let t = globals[head] * SIMD4<Float>(snoutTipInHead, 1)
            return SIMD3(t.x, t.y, t.z)
        }
        let headPosition = position(globals[head])
        let facing = simd_normalize(snoutTip() - headPosition)
        let toTarget = simd_normalize(target - headPosition)
        var desired = simd_normalize(facing * (1 - amount) + toTarget * amount)
        if simd_length(desired) < 0.5 || !desired.x.isFinite { desired = facing }

        var turn = simd_quatf(from: facing, to: desired)
        let limit: Float = 1.2
        if turn.angle > limit { turn = simd_quatf(angle: limit, axis: turn.axis) }
        turn = simd_quatf(angle: glance, axis: up) * turn

        // Spread the turn along the neck; children follow their parents.
        let localNeck2 = globals[neck1].inverse * globals[neck2]
        let localHead = globals[neck2].inverse * globals[head]
        let identity = simd_quatf(angle: 0, axis: [0, 0, 1])
        for (joint, share) in [(neck1, Float(0.35)), (neck2, Float(0.35)), (head, Float(0.3))] {
            let part = simd_slerp(identity, turn, share)
            let g = globals[joint]
            globals[joint] = matrix(rotation: simd_float3x3(part) * rotation(g), translation: position(g))
            if joint == neck1 { globals[neck2] = globals[neck1] * localNeck2 }
            if joint != head { globals[head] = globals[neck2] * localHead }
        }
    }

    private var legSolves = 0
    private var plantedOutOfReach = 0

    private func solveLeg(_ leg: Leg, target: SIMD3<Float>, footYaw: Float, droop: Float = 0,
                          globals: inout [simd_float4x4]) {
        let a = position(globals[leg.root])
        let toTarget = target - a
        let rawDistance = simd_length(toTarget)
        // Diagnostics: a planted foot the leg can't reach gets dragged along (looks like sliding).
        legSolves += 1
        if droop < 0.001, rawDistance > (leg.upper + leg.lower) * 0.995 { plantedOutOfReach += 1 }
        if legSolves >= 800 {
            print("Monitor Lizard: planted feet out of reach \(plantedOutOfReach * 100 / legSolves)% of the time")
            legSolves = 0
            plantedOutOfReach = 0
        }
        guard rawDistance > 0.000_1 else { return }
        let d = min(max(rawDistance, abs(leg.upper - leg.lower) + 0.000_1), leg.upper + leg.lower - 0.000_1)
        let direction = toTarget / rawDistance
        let along = (leg.upper * leg.upper - leg.lower * leg.lower + d * d) / (2 * d)
        let height = sqrt(max(leg.upper * leg.upper - along * along, 0))
        var bend = leg.outward - direction * simd_dot(leg.outward, direction)
        bend = simd_length(bend) > 0.000_1 ? simd_normalize(bend) : leg.outward
        let knee = a + direction * along + bend * height
        let reachedTarget = a + direction * d

        // Upper bone: swing so the knee/elbow lands at `knee`.
        let midNow = position(globals[leg.root] * restLocal[leg.mid])
        let q1 = simd_quatf(from: simd_normalize(midNow - a), to: simd_normalize(knee - a))
        globals[leg.root] = matrix(rotation: simd_float3x3(q1) * rotation(globals[leg.root]), translation: a)

        // Lower bone: swing so the wrist/ankle lands on the target.
        globals[leg.mid] = globals[leg.root] * restLocal[leg.mid]
        let endNow = position(globals[leg.mid] * restLocal[leg.end])
        let q2 = simd_quatf(from: simd_normalize(endNow - knee), to: simd_normalize(reachedTarget - knee))
        globals[leg.mid] = matrix(rotation: simd_float3x3(q2) * rotation(globals[leg.mid]), translation: knee)

        // Hand/foot stays flat and lined up with the body, so the toes don't swivel with the shin.
        let ankle = position(globals[leg.mid] * restLocal[leg.end])
        var level = simd_float3x3(simd_quatf(angle: footYaw, axis: up)) * rotation(restGlobal[leg.end])
        if droop > 0.001 {
            // Tip the toes down: turn about the horizontal axis across the foot
            // (the bone runs along its own Y axis, toward the toes).
            let toes = level.columns.1
            let flatToes = toes - up * simd_dot(toes, up)
            if simd_length(flatToes) > 0.001 {
                let across = simd_normalize(simd_cross(up, simd_normalize(flatToes)))
                level = simd_float3x3(simd_quatf(angle: droop, axis: across)) * level
            }
        }
        globals[leg.end] = matrix(rotation: level, translation: ankle)
    }

    /// Bends the tail bones down (about horizontal axes only, so the sideways wave is kept)
    /// so the tail slopes from the hips to the ground over its first third, then lies along it.
    private func dropTail(toFloorAt floorHeight: Float, pointsPerUnit ppu: Float,
                          globals: inout [simd_float4x4]) {
        let joints = tailJoints
        guard joints.count >= 2 else { return }
        // Each tail bone's offset from the one before, as posed so far.
        var locals: [simd_float4x4] = [matrix_identity_float4x4]
        for k in 1..<joints.count { locals.append(globals[joints[k - 1]].inverse * globals[joints[k]]) }
        let tipInLast = SIMD4<Float>(tailTipInLast, 1)
        /// Where the tail tip is, given the last tail bone's transform.
        func tip(_ m: simd_float4x4) -> SIMD3<Float> { let v = m * tipInLast; return SIMD3(v.x, v.y, v.z) }

        let baseHeight = simd_dot(position(globals[joints[0]]), up)
        // Total tail length, to measure how far along each joint is.
        var lengths: [Float] = []
        for k in 0..<joints.count {
            let child = k + 1 < joints.count ? position(globals[joints[k]] * locals[k + 1])
                                             : tip(globals[joints[k]])
            lengths.append(simd_length(child - position(globals[joints[k]])))
        }
        let total = max(lengths.reduce(0, +), 0.0001)
        let baseRadius = 3.0 / ppu, tipRadius = 0.6 / ppu
        let baseLift = max(baseHeight - floorHeight - baseRadius, 0)

        var along: Float = 0
        for k in 0..<joints.count {
            if k > 0 { globals[joints[k]] = globals[joints[k - 1]] * locals[k] }
            let g = globals[joints[k]]
            let p = position(g)
            let child = k + 1 < joints.count ? position(g * locals[k + 1]) : tip(g)
            along += lengths[k]
            let s = along / total                                        // 0 at the hips … 1 at the tip
            let fall = Float(1) - min(s / 0.35, 1)
            let ease = fall * fall * (3 - 2 * fall)                      // 1 near the hips, 0 by a third
            let radius = baseRadius + (tipRadius - baseRadius) * s
            let wanted = floorHeight + radius + baseLift * ease          // the child joint's height

            let v = child - p
            let length = simd_length(v)
            guard length > 0.000_1 else { continue }
            let vertical = simd_dot(v, up)
            let flat = v - up * vertical
            guard simd_length(flat) > 0.000_1 else { continue }
            let newVertical = min(max(wanted - simd_dot(p, up), -0.9 * length), 0.9 * length)
            let newFlat = sqrt(max(length * length - newVertical * newVertical, 0))
            let target = simd_normalize(flat) * newFlat + up * newVertical
            let q = simd_quatf(from: v / length, to: simd_normalize(target))
            globals[joints[k]] = matrix(rotation: simd_float3x3(q) * rotation(g), translation: p)
        }
    }

    // MARK: - Matrix helpers

    private func position(_ m: simd_float4x4) -> SIMD3<Float> { [m.columns.3.x, m.columns.3.y, m.columns.3.z] }

    private func rotation(_ m: simd_float4x4) -> simd_float3x3 {
        simd_float3x3(columns: (
            simd_normalize(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)),
            simd_normalize(SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)),
            simd_normalize(SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))))
    }

    private func matrix(rotation r: simd_float3x3, translation t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(r.columns.0, 0), SIMD4(r.columns.1, 0), SIMD4(r.columns.2, 0), SIMD4(t, 1)))
    }
}
