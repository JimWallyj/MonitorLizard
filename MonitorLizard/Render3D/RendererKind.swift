//
//  RendererKind.swift
//  MonitorLizard
//
//  Phase 1 step 2 test switch: which drawing method the habitat uses.
//  Saved in UserDefaults so the choice survives relaunches.
//

enum RendererKind: String, CaseIterable, Identifiable {
    case canvas2D
    case realityView
    case arView
    case manual3D
    case realModel

    static let storageKey = "rendererKind"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .canvas2D:    "2D (Canvas)"
        case .realityView: "3D (RealityView)"
        case .arView:      "3D (ARView)"
        case .manual3D:    "3D stand-in (Manual, capped)"
        case .realModel:   "3D Real lizard – recommended"
        }
    }
}
