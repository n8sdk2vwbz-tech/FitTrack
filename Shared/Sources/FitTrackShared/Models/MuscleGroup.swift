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
    case adductors
    case abductors
    case traps
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
        case .adductors: return "Adduktoren"
        case .abductors: return "Abduktoren"
        case .traps: return "Nacken/Trapez"
        case .cardio: return "Herz-Kreislauf"
        }
    }

    /// Grobe Körperregion, u.a. für die Muskel-Heatmap-Darstellung.
    public var bodyRegion: BodyRegion {
        switch self {
        case .chest, .shoulders, .triceps, .biceps, .forearms, .upperBack, .lats, .traps:
            return .upperBody
        case .abs, .obliques, .lowerBack:
            return .core
        case .glutes, .quads, .hamstrings, .calves, .adductors, .abductors:
            return .lowerBody
        case .cardio:
            return .cardio
        }
    }

    /// Grober Richtwert, wie viele Stunden nach einer trainierten Einheit bis
    /// zur Erholung vergehen - größere Muskelgruppen brauchen länger als
    /// kleinere/isolierte (Forschung zu größenabhängigen Erholungsfenstern:
    /// ca. 48h für kleinere, ca. 72h für größere Muskelgruppen bei einer
    /// echten Trainingsbelastung, DOMS-Rückbildung bei Mehrgelenksübungen
    /// nach ca. 72h). Bewusst ein grober Richtwert ohne Berücksichtigung der
    /// tatsächlichen Intensität der letzten Einheit - siehe
    /// `MuscleLoadStatus.recoveryHoursRemaining` für die Verwendung.
    public var typicalRecoveryHours: Double {
        switch self {
        case .quads, .hamstrings, .glutes, .chest, .lats, .upperBack, .lowerBack:
            return 72
        case .biceps, .triceps, .shoulders, .forearms, .calves, .abs, .obliques, .traps, .adductors, .abductors:
            return 48
        case .cardio:
            return 24
        }
    }
}

public enum BodyRegion: String, Codable, CaseIterable {
    case upperBody, core, lowerBody, cardio
}
