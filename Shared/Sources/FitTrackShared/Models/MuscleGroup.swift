import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest
    case upperBack
    case lowerBack
    case lats
    case shoulders
    case biceps
    case triceps
    case forearms
    case abs
    case obliques
    case glutes
    case quads
    case hamstrings
    case calves
    case traps
    case neck
    case cardio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chest: return "Brust"
        case .upperBack: return "Oberer Rücken"
        case .lowerBack: return "Unterer Rücken"
        case .lats: return "Latissimus"
        case .shoulders: return "Schultern"
        case .biceps: return "Bizeps"
        case .triceps: return "Trizeps"
        case .forearms: return "Unterarme"
        case .abs: return "Bauch"
        case .obliques: return "Seitliche Bauchmuskeln"
        case .glutes: return "Gesäß"
        case .quads: return "Quadrizeps"
        case .hamstrings: return "Beinbeuger"
        case .calves: return "Waden"
        case .traps: return "Nacken/Trapez"
        case .neck: return "Nacken"
        case .cardio: return "Herz-Kreislauf"
        }
    }

    /// Grobe Körperregion, u.a. für die Muskel-Heatmap-Darstellung.
    public var bodyRegion: BodyRegion {
        switch self {
        case .chest, .shoulders, .triceps, .biceps, .forearms, .upperBack, .lats, .traps, .neck:
            return .upperBody
        case .abs, .obliques, .lowerBack:
            return .core
        case .glutes, .quads, .hamstrings, .calves:
            return .lowerBody
        case .cardio:
            return .cardio
        }
    }
}

public enum BodyRegion: String, Codable, CaseIterable {
    case upperBody, core, lowerBody, cardio
}
