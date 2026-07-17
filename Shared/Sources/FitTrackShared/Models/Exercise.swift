import Foundation

public enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case mobility

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength: return "Kraft"
        case .cardio: return "Ausdauer"
        case .mobility: return "Mobilität"
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Identifiable {
    case none
    case barbell
    case dumbbell
    case kettlebell
    case machine
    case cable
    case bodyweight
    case band
    case bike
    case treadmill

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "Kein Gerät"
        case .barbell: return "Langhantel"
        case .dumbbell: return "Kurzhantel"
        case .kettlebell: return "Kettlebell"
        case .machine: return "Maschine"
        case .cable: return "Kabelzug"
        case .bodyweight: return "Körpergewicht"
        case .band: return "Widerstandsband"
        case .bike: return "Fahrrad"
        case .treadmill: return "Laufband"
        }
    }
}

/// Bestimmt, wie das im Training eingegebene Gewicht in das tatsächliche
/// Arbeitsgewicht umgerechnet wird (siehe `Exercise.effectiveWeight`).
public enum ExerciseLoadType: String, Codable {
    /// Eingegebenes Gewicht ist das Arbeitsgewicht (Standard, z.B. Langhantel/Kurzhantel/Maschine).
    case external
    /// Eingegebenes Gewicht wird zusätzlich zum Körpergewicht getragen (z.B. Klimmzüge/Dips mit Zusatzgewicht).
    case bodyweightPlus
    /// Eingegebenes Gewicht ist die Entlastung durch ein Gegengewicht und wird vom
    /// Körpergewicht abgezogen (z.B. unterstützende Klimmzug-/Dip-Maschine).
    case bodyweightMinus

    public var displayName: String {
        switch self {
        case .external: return "Gewicht"
        case .bodyweightPlus: return "Zusatzgewicht"
        case .bodyweightMinus: return "Unterstützung (Gegengewicht)"
        }
    }
}

/// Statische Übungs-Definition aus der Bibliothek. Kein SwiftData-Modell,
/// da diese Daten fest mit der App ausgeliefert werden und auf iPhone
/// und Watch identisch verfügbar sein müssen, ohne Sync-Bedarf.
public struct Exercise: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let category: ExerciseCategory
    public let equipment: Equipment
    public let primaryMuscles: [MuscleGroup]
    public let secondaryMuscles: [MuscleGroup]
    public let instructions: String
    public let loadType: ExerciseLoadType
    /// Einseitig ausgeführt (z.B. einarmiges Rudern) - das eingegebene Gewicht
    /// gilt pro Seite, beide Seiten werden im selben Satz trainiert, tragen
    /// also beide zur Belastung bei (siehe `effectiveWeight`/Verwendung in
    /// `SetEntry.volume`).
    public let isUnilateral: Bool

    public init(id: String, name: String, category: ExerciseCategory, equipment: Equipment, primaryMuscles: [MuscleGroup], secondaryMuscles: [MuscleGroup], instructions: String, loadType: ExerciseLoadType = .external, isUnilateral: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
        self.loadType = loadType
        self.isUnilateral = isUnilateral
    }

    public var allMuscles: [MuscleGroup] {
        primaryMuscles + secondaryMuscles
    }

    /// Rechnet ein eingegebenes Trainingsgewicht anhand von `loadType` in das
    /// tatsächliche Arbeitsgewicht um. `bodyWeightKg` kommt aus `BodyWeightCache`
    /// (best-effort aus Health) - ist es nicht bekannt, wird ein grober
    /// 70-kg-Richtwert angenommen, damit `.bodyweightPlus`/`.bodyweightMinus`
    /// auch ohne Health-Zugriff eine plausible (wenn auch ungenaue) Belastung ergeben.
    public func effectiveWeight(enteredWeightKg: Double, bodyWeightKg: Double?) -> Double {
        switch loadType {
        case .external:
            return enteredWeightKg > 0 ? enteredWeightKg : 20 // Körpergewichts-Näherung, falls kein Gewicht erfasst wurde
        case .bodyweightPlus:
            return (bodyWeightKg ?? 70) + enteredWeightKg
        case .bodyweightMinus:
            return max((bodyWeightKg ?? 70) - enteredWeightKg, 0)
        }
    }
}
